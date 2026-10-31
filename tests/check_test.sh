#!/usr/bin/env bash
# scripts/check.sh over a fixture tree with every tool faked: each check runs
# on the right paths, a failure is counted and annotated, and each template is
# linted as every target receives it.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A fake tool logging "<name> <args>" to $T/tools.log, copying any rendered
# template it is handed to $T/rendered.log, and failing when FAIL names it.
# Asked its version, it is 1.0.0, or 0.9.0 when STALE names it.
tool() {
  t_fake "$1" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0")"
case $* in --version | version)
  case " ${STALE:-} " in *" $name "*) echo "$name 0.9.0" ;; *) echo "$name v1.0.0" ;; esac
  exit 0
  ;;
esac
echo "$name $*" >>"$T/tools.log"
for f; do
  case $f in */ci-tmp.??????/render/*) { echo "== ${f#*/ci-tmp.??????/render/}" && cat "$f"; } >>"$T/rendered.log" ;; esac
done
case " ${FAIL:-} " in *" $name "*) exit 1 ;; esac
exit 0
EOF
}

# A fake npm whose audit answers $T/npm-audit.json, exiting 1 as npm does on a
# finding, else a clean report; FAIL names it to fail before any report.
npm_fake() {
  t_fake npm <<'EOF'
#!/usr/bin/env bash
echo "npm $*" >>"$T/tools.log"
case " ${FAIL:-} " in *" npm "*) echo "npm ERR! registry unreachable" >&2 && exit 1 ;; esac
cat "$T/npm-audit.json" 2>/dev/null || echo '{"metadata":{"vulnerabilities":{"total":0}},"vulnerabilities":{}}'
[ ! -e "$T/npm-audit.json" ]
EOF
}

# Target a receives a template workflow (values and a block), a plain
# workflow and a non-workflow file; target b receives the template alone. The
# tree keeps its own copies of codeql.yml, link-check.yml, rerun-timeouts.yml,
# scorecard.yml, tool-versions.yml, dependabot.yml, .gitignore and REUSE.toml.
fixture() {
  local t
  for t in shellcheck shfmt constricter actionlint zizmor lychee typos gitleaks reuse pip-audit; do tool "$t"; done
  npm_fake
  mkdir -p "$T/tree/scripts" "$T/tree/tests" "$T/tree/.github/scripts" \
    "$T/tree/.github/workflows" "$T/tree/.github/node_modules/.bin"
  echo 'true' >"$T/tree/scripts/s.sh"
  echo 'true' >"$T/tree/tests/t_test.sh"
  echo 'on: push' >"$T/tree/.github/workflows/own.yml"
  printf 'on: push\n# the setup-tools step\n          tools: shellcheck gitleaks\n' >"$T/tree/.github/workflows/checks.yml"
  cat >"$T/tree/.github/workflows/sync.yml" <<'EOF'
on: push
          repositories: a
          TOKEN_A: ${{ steps.app-a.outputs.token }}
          repositories: b
          TOKEN_B: ${{ steps.app-b.outputs.token }}
EOF
  printf '# a comment\nshellcheck|1.0.0|raw|u|--version|g||%s\ngitleaks|1.0.0|raw|u|version|g||%s\n' \
    "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})" | t_shared .github/actions/setup-tool/tools.txt
  echo '{}' >"$T/tree/.github/zizmor.yml"
  : >"$T/tree/requirements-dev.txt"
  printf '[[IgnoredVulns]]\nid = "GHSA-vfj7-8cjw-p6xm"\n' | t_shared .github/osv-scanner.toml
  ln -s "$T/bin/actionlint" "$T/tree/.github/scripts/lint_workflows.sh"
  ln -s "$T/bin/actionlint" "$T/tree/.github/node_modules/.bin/prettier"
  ln -s "$T/bin/actionlint" "$T/tree/.github/node_modules/.bin/markdownlint-cli2"
  printf 'name: __Language__\n# shared:if language\nlang: __language__\n# shared:endif\n' |
    t_shared .github/workflows/codeql.yml
  printf '# shared:unless language\nactions-only: true\n# shared:endif\n' |
    t_shared .github/workflows/marked.yml
  echo 'on: push' | t_shared .github/workflows/plain.yml
  echo 'on: push' | t_shared .github/workflows/link-check.yml
  echo 'on: push' | t_shared .github/workflows/rerun-timeouts.yml
  echo 'on: push' | t_shared .github/workflows/scorecard.yml
  echo 'on: push' | t_shared .github/workflows/tool-versions.yml
  echo 'version: 2' | t_shared .github/dependabot.yml
  echo 'local/' | t_shared .gitignore
  echo 'version = 1' | t_shared REUSE.toml
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
  "$SCRIPTS/own_files.sh"
  t_git "$T/tree" init -q
}

test_runs_every_check_over_the_tree() {
  fixture
  # lychee reads the tracked Markdown alone
  echo '# t' >"$T/tree/README.md"
  echo '# u' >"$T/tree/untracked.md"
  t_git "$T/tree" add README.md
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_out "== pins" "== shellcheck" "== markdownlint" "== lychee" "== typos" "== gitleaks" "== reuse" "== audit" "== usage" "== own-files" \
    "== config" "== mint" "== lint-workflows-rendered"
  t_no_out "::error"
  t_in -x "$T/tools.log" 'shellcheck -x files/.github/scripts/shared.sh scripts/s.sh tests/t_test.sh' \
    'constricter scripts tests' \
    'lychee --config lychee.toml --offline --include-fragments --no-progress README.md' \
    'typos ' 'gitleaks git --redact --no-banner .' 'reuse --no-multiprocessing lint' \
    'pip-audit --strict --require-hashes --disable-pip -r requirements-dev.txt' 'npm audit --prefix .github --json' \
    'zizmor --config .github/zizmor.yml --offline .github/workflows files/.github' \
    'prettier --check .' \
    'lint_workflows.sh .github/workflows/checks.yml .github/workflows/codeql.yml .github/workflows/link-check.yml .github/workflows/own.yml .github/workflows/rerun-timeouts.yml .github/workflows/scorecard.yml .github/workflows/sync.yml .github/workflows/tool-versions.yml files/.github/workflows/link-check.yml files/.github/workflows/plain.yml files/.github/workflows/rerun-timeouts.yml files/.github/workflows/scorecard.yml files/.github/workflows/tool-versions.yml files/.github/actions/a/action.yml'
  # the renderings read the shared runner labels and prettier config
  t_match "$T/tools.log" '^actionlint -config-file .github/actionlint.yaml .*/ci-tmp\.[^/]*/render/' \
    '^prettier --check --config .prettierrc.yaml .*/ci-tmp\.[^/]*/render/'
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
  t_target b dev docs/t.md
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_out "== markdownlint-rendered"
  t_no_out "actionlint-rendered"
  # the raw template is kept from prettier and markdownlint
  t_in -x "$T/tools.log" 'prettier --check . !files/docs/t.md' 'markdownlint-cli2 **/*.md #**/node_modules #.claude #local #files/docs/t.md'
  t_match "$T/tools.log" '^markdownlint-cli2 --config .markdownlint.yaml .*/a/docs/t.md .*/b/docs/t.md$'
  # every rendering, a file prettier has no parser for included: --ignore-unknown skips it
  t_match "$T/tools.log" '^prettier --check --config .prettierrc.yaml --ignore-unknown .*/a/.gitattributes .*/a/docs/t.md .*/b/docs/t.md$'
  # prettier sees every rendering (a's .gitattributes keeps its block on the
  # implicit repo alone), markdownlint the Markdown alone
  t_file "$T/rendered.log" "$(
    cat <<'EOF'
== a/.gitattributes
*.apk binary
== a/docs/t.md
# a

- only a
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
  t_target b dev .vscode/settings.json
  "$SCRIPTS/usage.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  # the raw template is kept from prettier; markdownlint's raw list is unchanged
  t_in -x "$T/tools.log" 'prettier --check . !files/.vscode/settings.json' 'markdownlint-cli2 **/*.md #**/node_modules #.claude #local'
  t_match "$T/tools.log" '^prettier --check --config .prettierrc.yaml --ignore-unknown .*/a/.vscode/settings.json .*/b/.vscode/settings.json$'
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
  t_run env FAIL="shellcheck zizmor pip-audit" GH_TOKEN=t "$SCRIPTS/check.sh"
  t_rc 3
  t_out "::error title=shellcheck::shellcheck failed" "::error title=zizmor::zizmor failed" \
    "::error title=audit::audit failed"
  # online, with a token
  t_in -x "$T/tools.log" 'zizmor --config .github/zizmor.yml .github/workflows files/.github'
}

test_a_target_without_a_mint_step_or_token_line_fails() {
  fixture
  sed -i -e '/repositories: b/d' "$T/tree/.github/workflows/sync.yml"
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "b has no mint step or TOKEN_B line in .github/workflows/sync.yml" "::error title=mint::mint failed"
  t_no_out "a has no mint step"
  # shellcheck disable=SC2016 # the workflow's own expression
  printf '          repositories: a\n          repositories: b\n          TOKEN_B: ${{ steps.app-b.outputs.token }}\n' >"$T/tree/.github/workflows/sync.yml"
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "a has no mint step or TOKEN_A line in .github/workflows/sync.yml"
}

test_a_tool_off_its_pin_fails() {
  fixture
  t_run env STALE=gitleaks "$SCRIPTS/check.sh"
  t_rc 1
  t_out "gitleaks is not the pinned 1.0.0: gitleaks 0.9.0" "::error title=pins::pins failed"
  t_no_out "shellcheck is not the pinned"
}

test_a_tool_missing_or_without_a_row_fails() {
  fixture
  printf 'on: push\n          tools: shellcheck nosuchtool typos\n' >"$T/tree/.github/workflows/checks.yml"
  echo "nosuchtool|1.0.0|raw|u|--version|g||$(printf 'c%.0s' {1..64})" >>"$T/tree/files/.github/actions/setup-tool/tools.txt"
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "nosuchtool is not the pinned 1.0.0: " "setup-tool: no row for 'typos'" "::error title=pins::pins failed"
}

test_a_shared_file_the_template_gitignore_swallows_fails() {
  fixture
  # a target's blanket rule in the shared .gitignore applies to files/ here
  printf '# shared:if repo=a\n*.toml\n# shared:endif\n' | t_shared .gitignore
  echo 'x = 1' | t_shared tool.toml
  echo 'x = 1' | t_shared .github/kept.toml
  t_target b dev tool.toml .github/kept.toml
  "$SCRIPTS/usage.sh"
  "$SCRIPTS/own_files.sh"
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "files/tool.toml is ignored by files/.gitignore: negate the rule in the template" \
    "files/.github/kept.toml is ignored" "::error title=ignored::ignored failed"
  # negated in the template, the file reaches a commit again; one already
  # tracked is past the rules
  printf '# shared:if repo=a\n*.toml\n!tool.toml\n# shared:endif\n' | t_shared .gitignore
  "$SCRIPTS/own_files.sh"
  t_git "$T/tree" add -f files/.github/kept.toml
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_no_out "is ignored"
}

test_an_npm_advisory_fails_unless_accepted() {
  fixture
  # one accepted id and one not, the second reached through a dependency name
  # as well as its url
  cat >"$T/npm-audit.json" <<'EOF'
{"metadata":{"vulnerabilities":{"total":2}},"vulnerabilities":{
  "braces":{"via":[{"url":"https://github.com/advisories/GHSA-vfj7-8cjw-p6xm"}]},
  "micromatch":{"via":["braces",{"url":"https://github.com/advisories/GHSA-0000-open-0000"}]}}}
EOF
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out "npm audit reports advisories files/.github/osv-scanner.toml does not accept:" "GHSA-0000-open-0000" \
    "::error title=audit::audit failed"
  t_no_out "GHSA-vfj7-8cjw-p6xm"
}

test_an_accepted_npm_advisory_alone_passes() {
  fixture
  cat >"$T/npm-audit.json" <<'EOF'
{"metadata":{"vulnerabilities":{"total":1}},"vulnerabilities":{
  "braces":{"via":[{"url":"https://github.com/advisories/GHSA-vfj7-8cjw-p6xm"}]}}}
EOF
  t_run "$SCRIPTS/check.sh"
  t_rc 0
  t_no_out "npm audit reports"
}

test_an_npm_audit_that_did_not_run_fails() {
  fixture
  t_run env FAIL=npm "$SCRIPTS/check.sh"
  t_rc 1
  t_out "npm ERR! registry unreachable" "npm audit did not run" "::error title=audit::audit failed"
}

test_an_empty_token_is_unset_for_zizmor() {
  fixture
  # zizmor reads GH_TOKEN itself and refuses an empty one
  t_fake zizmor <<'EOF'
#!/usr/bin/env bash
[ -z "${GH_TOKEN+set}" ] || { echo "GH_TOKEN is set to '$GH_TOKEN'"; exit 1; }
echo "zizmor $*" >>"$T/tools.log"
EOF
  t_run env GH_TOKEN= "$SCRIPTS/check.sh"
  t_rc 0
  t_in -x "$T/tools.log" 'zizmor --config .github/zizmor.yml --offline .github/workflows files/.github'
}

test_a_stale_own_file_fails() {
  fixture
  echo 'on: pull_request' | t_shared .github/workflows/scorecard.yml
  t_run "$SCRIPTS/check.sh"
  t_rc 1
  t_out ".github/workflows/scorecard.yml is out of date" "::error title=own-files::own-files failed"
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
