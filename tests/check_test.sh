#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check.sh over a fixture tree with every tool faked: each check runs
# on the right paths, a failure is counted and annotated, and each template is
# linted as every target receives it.
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
  t_in -x "$T/tools.log" 'shellcheck -x files/.github/scripts/shared.sh scripts/s.sh tests/t_test.sh' \
    'zizmor --config .github/zizmor.yml --offline .github/workflows files/.github' \
    'prettier --check .' \
    'lint_workflows.sh .github/workflows/own.yml files/.github/workflows/plain.yml files/.github/actions/a/action.yml'
  grep -q '^prettier --check --config .prettierrc.yaml .*/ci-render\.' "$T/tools.log" ||
    t_fail "prettier did not run on the renderings with the shared config"
  # prettier, actionlint and lint_workflows.sh each see every rendering
  t_file "$T/rendered.log" "$(
    for _ in 1 2 3; do
      cat <<'EOF'
== a/.github/workflows/codeql.yml
name: Rust
lang: rust
== b/.github/workflows/marked.yml
actions-only: true
EOF
    done
  )"
}

test_lints_a_markdown_template_rendered_not_raw() {
  fixture
  printf '# __repo__\n\n<!-- shared:if repo=a -->\n- only a\n<!-- shared:endif -->\n' | t_shared docs/t.md
  printf '# shared:if repo=a\n*.apk binary\n# shared:endif\n' | t_shared .gitattributes
  t_target a dev .github/workflows/plain.yml docs/t.md .gitattributes
  t_toml a <<'EOF'
[templates."docs/t.md"]
repo = "a"
EOF
  t_target b dev docs/t.md
  t_toml b <<'EOF'
[templates."docs/t.md"]
repo = "b"
EOF
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_out "== markdownlint-rendered"
  t_no_out "actionlint-rendered"
  # the raw template is kept from prettier and markdownlint
  t_in -x "$T/tools.log" 'prettier --check . !files/docs/t.md' 'markdownlint-cli2 **/*.md #**/node_modules #files/docs/t.md'
  grep -q '^markdownlint-cli2 --config .markdownlint.yaml .*/a/docs/t.md .*/b/docs/t.md$' "$T/tools.log" ||
    t_fail "markdownlint did not run on the renderings: $(grep '^markdownlint' "$T/tools.log")"
  # every rendering, a file prettier has no parser for included: --ignore-unknown skips it
  grep -q '^prettier --check --config .prettierrc.yaml --ignore-unknown .*/a/docs/t.md .*/a/.gitattributes .*/b/docs/t.md$' "$T/tools.log" ||
    t_fail "prettier's rendered paths: $(grep '^prettier --check --config' "$T/tools.log")"
  # prettier sees every rendering (a's .gitattributes renders empty: no
  # value keeps its block), markdownlint the Markdown alone
  t_file "$T/rendered.log" "$(
    cat <<'EOF'
== a/docs/t.md
# a

- only a
== a/.gitattributes
== b/docs/t.md
# b

== a/docs/t.md
# a

- only a
== b/docs/t.md
# b

EOF
  )"
}

test_lints_a_json_template_rendered_not_raw() {
  fixture
  printf '{\n# shared:if repo=a\n  "a": true,\n# shared:endif\n  "b": true\n}\n' | t_shared .vscode/settings.json
  t_target a dev .github/workflows/plain.yml .vscode/settings.json
  t_toml a <<'EOF'
[templates.".vscode/settings.json"]
repo = "a"
EOF
  t_target b dev .vscode/settings.json
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  # the raw template is kept from prettier; markdownlint's raw list is unchanged
  t_in -x "$T/tools.log" 'prettier --check . !files/.vscode/settings.json' 'markdownlint-cli2 **/*.md #**/node_modules'
  grep -q '^prettier --check --config .prettierrc.yaml --ignore-unknown .*/a/.vscode/settings.json .*/b/.vscode/settings.json$' "$T/tools.log" ||
    t_fail "prettier did not run on the renderings: $(grep '^prettier --check --config' "$T/tools.log")"
  t_file "$T/rendered.log" "$(
    cat <<'EOF'
== a/.vscode/settings.json
{
  "a": true,
  "b": true
}
== b/.vscode/settings.json
{
  "b": true
}
EOF
  )"
}

test_a_value_a_target_lacks_fails() {
  fixture
  printf 'name: __tool__\n# shared:if tool\nrun: __tool__\n# shared:endif\n' | t_shared .github/workflows/u.yml
  t_target a dev .github/workflows/u.yml
  t_toml a <<'EOF'
[templates.".github/workflows/u.yml"]
tool = "t"
EOF
  t_target b dev .github/workflows/u.yml
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "b/.github/workflows/u.yml leaves __tool__ unrendered" "::error title=unrendered::unrendered failed"
  t_no_out "a/.github/workflows/u.yml leaves"
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
