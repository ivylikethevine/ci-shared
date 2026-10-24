#!/usr/bin/env bash
# Runs every suite under kcov and coverage.py, and fails unless every
# statement of scripts/*.sh and scratch/*.sh ran (tests/coverage.py says how a
# statement is judged from kcov's lines) and every line and branch of the
# Python in scripts/, tests/ and scratch/ did (pyproject.toml's
# [tool.coverage]). The checks workflow's coverage job runs it.
#
#   tests/coverage.sh [OUT]
#
# OUT, which must not exist yet (kcov adds to an earlier run's counts), gets
# kcov's reports and coverage.py's data; the default is a fresh temporary
# directory. Needs kcov 43 or later (Ubuntu 26.04's package) and shfmt, as
# tools.txt pins it, on PATH, and a
# python3 that imports coverage (requirements-dev.txt), besides what
# tests/run.sh needs.
set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ $# -gt 0 ]; then
  out=$1
  if [ -e "$out" ]; then
    echo "coverage: $out exists; kcov would add to its counts" >&2
    exit 2
  fi
  mkdir -p "$out"
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/ci-shared-coverage.XXXXXX")"
fi

python="$(command -v python3)"
"$python" -c 'import coverage' 2>/dev/null || {
  echo "coverage: $python cannot import coverage; install requirements-dev.txt" >&2
  exit 2
}
export COVERAGE_FILE="$out/python/.coverage"
mkdir -p "$out/python" "$out/bin" "$out/kcov"

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
  --source="$repo/scripts,$repo/tests,$repo/scratch" --parallel-mode "\$@" ;;
esac
exec "$python" \${opts[@]+"\${opts[@]}"} "\$@"
EOF
chmod +x "$out/bin/python3"

# One kcov run per suite, which coverage.py adds together: in one run over
# several suites, kcov loses the lines of some scripts (rulesets.sh) that each
# suite alone records, and its --merge drops the lines no suite hit.
rc=0
for suite in "$repo"/tests/*_test.sh; do
  suite="$(basename "$suite" _test.sh)"
  PATH="$out/bin:$PATH" kcov --include-path="$repo/scripts,$repo/scratch" \
    --bash-parse-files-in-dir="$repo/scripts,$repo/scratch" "$out/kcov/$suite" "$repo/tests/run.sh" "$suite" || rc=1
done
echo "reports: $out/kcov/<suite>/index.html"
"$python" -I "$repo/tests/coverage.py" "$out"/kcov/*/run.sh/cobertura.xml "$repo"/scripts/*.sh "$repo"/scratch/*.sh || rc=1
"$python" -m coverage combine --rcfile="$repo/pyproject.toml" --quiet "$out/python"
"$python" -m coverage report --rcfile="$repo/pyproject.toml" || rc=1
exit "$rc"
