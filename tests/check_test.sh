#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check.sh over a fixture tree with every tool faked: each check runs
# on the right paths, a failure is counted and annotated, and each workflow
# template is linted as every target receives it.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A fake tool logging "<name> <args>" to $T/tools.log, copying any rendered
# template it is handed to $T/rendered.log, and failing when FAIL names it.
tool() {
  t_fake "$1" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0")"
echo "$name $*" >>"$T/tools.log"
for f; do
  case $f in */ci-render.*) { echo "== ${f#*/ci-render.??????/}" && cat "$f"; } >>"$T/rendered.log" ;; esac
done
case " ${FAIL:-} " in *" $name "*) exit 1 ;; esac
exit 0
EOF
}

# Target a receives a template workflow (values and a block), a plain
# workflow and a non-workflow file; target b receives the template alone.
fixture() {
  local t
  for t in shellcheck shfmt actionlint zizmor; do tool "$t"; done
  mkdir -p "$T/tree/scripts" "$T/tree/tests" "$T/tree/.github/scripts" \
    "$T/tree/.github/workflows" "$T/tree/.github/node_modules/.bin"
  echo 'true' >"$T/tree/scripts/s.sh"
  echo 'true' >"$T/tree/tests/t_test.sh"
  echo 'on: push' >"$T/tree/.github/workflows/own.yml"
  echo '{}' >"$T/tree/.github/zizmor.yml"
  ln -s "$T/bin/actionlint" "$T/tree/.github/scripts/lint_workflows.sh"
  ln -s "$T/bin/actionlint" "$T/tree/.github/node_modules/.bin/prettier"
  ln -s "$T/bin/actionlint" "$T/tree/.github/node_modules/.bin/markdownlint-cli2"
  printf 'name: __Language__\n# shared:if language\nlang: __language__\n# shared:endif\n' |
    t_shared .github/workflows/codeql.yml
  printf '# shared:unless language\nactions-only: true\n# shared:endif\n' |
    t_shared .github/workflows/marked.yml
  echo 'on: push' | t_shared .github/workflows/plain.yml
  echo 'x' | t_shared .github/actions/a/action.yml
  echo 'true' | t_shared .github/scripts/shared.sh
  t_target a dev .github/workflows/codeql.yml .github/workflows/plain.yml .github/actions/a/action.yml
  t_toml a <<'EOF'
[templates.".github/workflows/codeql.yml"]
language = "rust"
Language = "Rust"
EOF
  t_target b dev .github/workflows/marked.yml
  "$SCRIPTS/usage.sh"
  # nothing tracked, so spdx.sh passes
  t_git "$T/tree" init -q
}

test_runs_every_check_over_the_tree() {
  fixture
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_out "== shellcheck" "== markdownlint" "== usage" "== spdx" "== config" "== lint-workflows-rendered"
  t_no_out "::error"
  grep -qxF 'shellcheck -x files/.github/scripts/shared.sh scripts/s.sh tests/t_test.sh' "$T/tools.log" ||
    t_fail "shellcheck's paths: $(grep '^shellcheck' "$T/tools.log")"
  grep -qxF 'zizmor --config .github/zizmor.yml --offline .github/workflows files/.github' "$T/tools.log" ||
    t_fail "zizmor's arguments: $(grep '^zizmor' "$T/tools.log")"
  grep -qxF 'prettier --check .' "$T/tools.log" || t_fail "prettier did not run on the tree"
  t_eq "$(cat "$T/rendered.log")" "$(
    cat <<'EOF'
== a/.github/workflows/codeql.yml
name: Rust
lang: rust
== b/.github/workflows/marked.yml
actions-only: true
== a/.github/workflows/codeql.yml
name: Rust
lang: rust
== b/.github/workflows/marked.yml
actions-only: true
EOF
  )" "the rendered templates"
}

test_counts_and_annotates_each_failure() {
  fixture
  t_run env FAIL="shellcheck zizmor" GH_TOKEN=t "$SCRIPTS/check.sh"
  t_rc 2
  t_out "::error title=shellcheck::shellcheck failed" "::error title=zizmor::zizmor failed"
  grep -qxF 'zizmor --config .github/zizmor.yml .github/workflows files/.github' "$T/tools.log" ||
    t_fail "zizmor ran offline with a token"
}

test_an_invalid_config_fails_and_renders_nothing() {
  fixture
  t_target c dev missing.yml
  t_run "$SCRIPTS/check.sh"
  t_rc 2
  t_out "::error title=usage::usage failed" "::error title=config::config failed" "ci_load has not run"
  t_no_out "rendered"
}

test_no_templates_no_rendered_checks() {
  fixture
  t_target a dev .github/workflows/plain.yml
  rm "$T/tree/repos/b.toml"
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_no_out "rendered"
}

t_main
