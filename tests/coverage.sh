#!/usr/bin/env bash
# Runs every suite under bashcov and coverage.py, and fails unless every
# statement of scripts/*.sh ran (tests/coverage.py says how a statement is
# judged from bashcov's lines) and every line and branch of the Python in
# scripts/ and tests/ did (pyproject.toml's [tool.coverage]). The checks
# workflow's coverage job runs it.
#
#   tests/coverage.sh [OUT]
#
# OUT, which must not exist yet (SimpleCov adds to an earlier run's
# resultset), gets each suite's bashcov report and coverage.py's data; the
# default is a fresh temporary directory. Needs bashcov (checks.yml's
# BASHCOV_VERSION, and ruby), shfmt as tools.txt pins it, and a python3 that
# imports coverage (requirements-coverage.txt), besides what tests/run.sh
# needs.
set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ $# -gt 0 ]; then
  out=$1
  if [ -e "$out" ]; then
    echo "coverage: $out exists; SimpleCov would add to its resultsets" >&2
    exit 2
  fi
  mkdir -p "$out"
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/ci-shared-coverage.XXXXXX")"
fi

# `gem install --user-install` puts bashcov off the default PATH
if ! command -v bashcov >/dev/null 2>&1; then
  for gems in "$HOME"/.local/share/gem/ruby/*/bin; do
    [ ! -x "$gems/bashcov" ] || PATH="$gems:$PATH"
  done
fi
command -v bashcov >/dev/null 2>&1 || {
  echo "coverage: no bashcov on PATH; gem install --user-install bashcov" >&2
  exit 2
}
python="$(command -v python3)"
"$python" -c 'import coverage' 2>/dev/null || {
  echo "coverage: $python cannot import coverage; install requirements-coverage.txt" >&2
  exit 2
}
export COVERAGE_FILE="$out/python/.coverage"
mkdir -p "$out/python" "$out/bin" "$out/bashcov"

# The suites run python3 from PATH, the shebangs included: a file of this
# repository runs under coverage, anything else as it is. The interpreter's
# own options, ahead of the file, are kept.
cat >"$out/bin/python3" <<EOF
#!/usr/bin/env bash
opts=()
while [ \$# -gt 0 ] && [ "\${1#-}" != "\$1" ] && [ "\$1" != - ]; do
  opts+=("\$1")
  shift
done
case \${1:-} in
$repo/*) exec "$python" \${opts[@]+"\${opts[@]}"} -m coverage run --rcfile="$repo/pyproject.toml" \\
  --source="$repo/scripts,$repo/tests" --parallel-mode "\$@" ;;
esac
exec "$python" \${opts[@]+"\${opts[@]}"} "\$@"
EOF
chmod +x "$out/bin/python3"

# SimpleCov reads its settings from the first .simplecov at or above the
# working directory, and writes into the tree unless told otherwise: each
# suite runs from its own directory under OUT, which this file sits above.
cat >"$out/.simplecov" <<'EOF'
SimpleCov.coverage_dir(Dir.getwd)
EOF

# One bashcov run per suite, side by side, each its own resultset, which
# coverage.py adds together. --skip-uncovered: a script no suite ran has no
# lines, so coverage.py reports its statements as not seen. Left out of the
# log: a line per fixture script a case ran and removed, and SimpleCov's
# summary, whose figure counts the tests too.
# shellcheck source=./parallel.sh
source "$repo/tests/parallel.sh"
run_one() (
  mkdir -p "$out/bashcov/$1"
  cd "$out/bashcov/$1"
  PATH="$out/bin:$PATH" BASH_ENV="$repo/tests/coverage_env.sh" bashcov --skip-uncovered \
    --root "$repo" --command-name "$1" -- "$repo/tests/run.sh" "$1" 2>&1 |
    { grep -vE '^(bashcov: warning: .* has been deleted since then|Run completed using |Coverage report generated for |Line coverage: )' || true; }
)
suites=()
for suite in "$repo"/tests/*_test.sh; do suites+=("$(basename "$suite" _test.sh)"); done
run_parallel "${suites[@]}"
rc=0
[ "$FAILED" = 0 ] || rc=1
echo "reports: $out/bashcov/<suite>/index.html"
"$python" -I "$repo/tests/coverage.py" "$out"/bashcov/*/.resultset.json "$repo"/scripts/*.sh || rc=1
"$python" -m coverage combine --rcfile="$repo/pyproject.toml" --quiet "$out/python"
"$python" -m coverage report --rcfile="$repo/pyproject.toml" || rc=1
exit "$rc"
