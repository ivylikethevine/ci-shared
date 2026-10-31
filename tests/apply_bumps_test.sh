#!/usr/bin/env bash
# scripts/apply_bumps.sh: each kind of fix-list line edits its pin, a line that
# cannot be applied is reported while the rest land, and the locks and own files
# are regenerated. curl, npm and pip-compile are faked.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck disable=SC2016 # the backticks are the printed Markdown's
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OLD_SHA="$(printf 'a%.0s' {1..40})"
NEW_SHA="$(printf 'b%.0s' {1..40})"

# A fake curl printing its URL, so an asset's sha256 is the URL's; FAIL names a
# URL to refuse.
fixture() {
  t_fake curl <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
[ "$url" != "${FAIL:-}" ] || exit 22
if [ -n "${SAME:-}" ]; then echo same; else echo "$url"; fi
EOF
  t_fake pip-compile <<'EOF'
#!/usr/bin/env bash
echo "pip-compile $*" >>"$T/tools.log"
[ -z "${PIP_FAIL:-}" ]
EOF
  t_fake npm <<'EOF'
#!/usr/bin/env bash
echo "npm $*" >>"$T/tools.log"
EOF
  mkdir -p "$T/tree/.github/workflows"
  printf '# a comment|with|bars\none|1.0|raw|https://x/%%v/one|--version|github:o/one||%s\nmany|1.0|tar.gz|https://x/%%v/%%a|--version|github:o/many||linux-x86_64:lin=%s,darwin-aarch64=%s\nkeep|1.0|raw|u|v|c||%s\n' \
    "$(printf '1%.0s' {1..64})" "$(printf '2%.0s' {1..64})" "$(printf '3%.0s' {1..64})" "$(printf '4%.0s' {1..64})" |
    t_shared .github/actions/setup-tool/tools.txt
  for f in codeql link-check scorecard rerun-timeouts tool-versions; do
    printf 'name: %s\n' "$f" | t_shared ".github/workflows/$f.yml"
  done
  printf '    - uses: o/act@%s # v1.0.0\n    - uses: o/act/sub@%s # v1.0.0\n    - uses: o/act@%s # v0.9.0\n    - uses: o/other@%s # v1.0.0\n' \
    "$OLD_SHA" "$OLD_SHA" "$OLD_SHA" "$OLD_SHA" | t_shared .github/workflows/scorecard.yml
  printf '    - uses: o/act@%s # v1.0.0\n' "$OLD_SHA" | t_shared .github/actions/a/action.yml
  printf '    - uses: o/act@%s # v1.0.0\n' "$OLD_SHA" >"$T/tree/.github/workflows/sync.yml"
  echo 'version: 2' | t_shared .github/dependabot.yml
  echo 'local/' | t_shared .gitignore
  echo 'version = 1' | t_shared REUSE.toml
  echo 'theme: t/t@v1.0' | t_shared _config.yml
  printf '{\n  "devDependencies": {\n    "lint": "1.0.0"\n  },\n  "overrides": {\n    "tex": "1.0.0"\n  }\n}\n' |
    t_shared .github/package.json
  ln -s ../files/.github/package.json "$T/tree/.github/package.json"
  printf 'requests-oauth==1.0.0\nkept==1.0.0\nrequests-oauth2==1.0.0\n' >"$T/tree/requirements-dev.in"
  printf 'cov==1.0.0\n' >"$T/tree/requirements-coverage.in"
}

# sha_of <url> - the fake curl's asset's sha256
sha_of() {
  echo "$1" | sha256sum | cut -d' ' -f1
}

test_a_tool_takes_its_pin_and_each_hash() {
  fixture
  printf 'tool|one|1.0|1.1||\ntool|many|1.0|2.0||\n' >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 0
  t_out '- `one` 1.0 to 1.1' '- `many` 1.0 to 2.0'
  t_in -x "$T/tree/files/.github/actions/setup-tool/tools.txt" '# a comment|with|bars' \
    "one|1.1|raw|https://x/%v/one|--version|github:o/one||$(sha_of https://x/1.1/one)" \
    "many|2.0|tar.gz|https://x/%v/%a|--version|github:o/many||linux-x86_64:lin=$(sha_of https://x/2.0/lin),darwin-aarch64=$(sha_of https://x/2.0/darwin-aarch64)" \
    "keep|1.0|raw|u|v|c||$(printf '4%.0s' {1..64})"
}

test_a_tool_that_cannot_be_hashed_stays_and_the_rest_land() {
  fixture
  printf 'tool|one|1.0|1.1||\ntool|many|1.0|2.0||\ntool|nosuch|1.0|2.0||\nodd|x|1|2||\n' >"$T/fixes"
  t_run env FAIL=https://x/2.0/lin "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 3
  t_out '- `one` 1.0 to 1.1' '- `many` 1.0 to 2.0: **not bumped**, do it by hand' \
    '::error title=bump many::could not bump tool many from 1.0 to 2.0; do it by hand' '- `nosuch` 1.0 to 2.0: **not bumped**' '- `x` 1 to 2: **not bumped**'
  t_in "$T/tree/files/.github/actions/setup-tool/tools.txt" 'many|1.0|'
  t_not_in "$T/tree/files/.github/actions/setup-tool/tools.txt" 'one|1.0|'
  t_run env FAIL=https://x/1.1/one "$SCRIPTS/apply_bumps.sh" <(printf 'tool|keep|1.0|1.1||\n')
  t_rc 1
}

test_a_tool_whose_hash_did_not_change_stays() {
  fixture
  printf 'one|1.0|raw|https://x/%%v/one|--version|github:o/one||%s\n' "$(sha_of same)" |
    t_shared .github/actions/setup-tool/tools.txt
  printf 'tool|one|1.0|1.1||\n' >"$T/fixes"
  t_run env SAME=1 "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 1
  t_in "$T/tree/files/.github/actions/setup-tool/tools.txt" 'one|1.0|'
}

test_an_action_moves_at_its_pin_everywhere() {
  fixture
  printf 'action|o/act|1.0.0|1.1.0|@%s # v1.1.0||\n' "$NEW_SHA" >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 0
  t_in -x "$T/tree/files/.github/workflows/scorecard.yml" "    - uses: o/act@$NEW_SHA # v1.1.0" "    - uses: o/act/sub@$NEW_SHA # v1.1.0" \
    "    - uses: o/act@$OLD_SHA # v0.9.0" "    - uses: o/other@$OLD_SHA # v1.0.0"
  t_in -x "$T/tree/files/.github/actions/a/action.yml" "    - uses: o/act@$NEW_SHA # v1.1.0"
  t_in -x "$T/tree/.github/workflows/sync.yml" "    - uses: o/act@$NEW_SHA # v1.1.0"
  # the own copies follow files/
  t_in -x "$T/tree/.github/workflows/scorecard.yml" "    - uses: o/act@$NEW_SHA # v1.1.0"
}

test_an_action_with_no_value_or_no_use_stays() {
  fixture
  printf 'action|o/act|1.0.0|1.1.0|||\naction|o/none|1.0.0|1.1.0|@%s # v1.1.0||\n' "$NEW_SHA" >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 2
  t_in "$T/tree/.github/workflows/sync.yml" "# v1.0.0"
}

test_an_inline_pin_moves_where_its_regex_matches() {
  fixture
  printf 'other: v1.0\n' | t_shared other.yml
  printf 'inline|theme|1.0|1.1||files/*.yml|theme: t/t@v\\([0-9.]*\\)\n' >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 0
  t_file "$T/tree/files/_config.yml" 'theme: t/t@v1.1'
  t_file "$T/tree/files/other.yml" 'other: v1.0'
  printf 'inline|theme|1.0|1.1||files/none*|theme\n' >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 1
}

test_npm_moves_the_manifest_through_its_symlink_and_refreshes_the_lock() {
  fixture
  printf 'npm|lint|1.0.0|1.1.0||.github/package.json|\nnpm|tex|1.0.0|1.2.0||.github/package.json|\nnpm|absent|1.0.0|1.2.0||.github/package.json|\n' >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 1
  t_out '- `absent` 1.0.0 to 1.2.0: **not bumped**'
  [ -L "$T/tree/.github/package.json" ] || t_fail "the symlink was replaced"
  t_eq "$(jq -c . "$T/tree/files/.github/package.json")" '{"devDependencies":{"lint":"1.1.0"},"overrides":{"tex":"1.2.0"}}' "the manifest"
  t_match "$T/tools.log" "^npm install --prefix .*/tree/files/.github --package-lock-only --ignore-scripts --no-audit --no-fund\$"
  [ "$(grep -c '^npm' "$T/tools.log")" = 1 ] || t_fail "npm ran more than once"
}

test_pip_moves_the_input_and_compiles_every_lock() {
  fixture
  printf 'Requests_OAuth==1.0.0\n' >"$T/tree/requirements-dev.in"
  printf 'pip|requests-oauth|1.0.0|1.1.0||requirements-dev.in|\npip|absent|1.0.0|1.1.0||requirements-dev.in|\n' >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 1
  t_file "$T/tree/requirements-dev.in" 'requests-oauth==1.1.0'
  t_file "$T/tools.log" 'pip-compile --quiet --allow-unsafe --generate-hashes --strip-extras requirements-coverage.in
pip-compile --quiet --allow-unsafe --generate-hashes --strip-extras requirements-dev.in'
}

test_a_lock_that_will_not_compile_fails() {
  fixture
  printf 'pip|cov|1.0.0|1.1.0||requirements-coverage.in|\n' >"$T/fixes"
  t_run env PIP_FAIL=1 "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 1
}

test_nothing_to_bump_changes_nothing() {
  fixture
  : >"$T/fixes"
  t_run "$SCRIPTS/apply_bumps.sh" "$T/fixes"
  t_rc 0
  [ ! -e "$T/tools.log" ] || t_fail "a tool ran"
}

test_usage() {
  t_run "$SCRIPTS/apply_bumps.sh"
  t_rc 2
  t_out "usage: apply_bumps.sh <fix list>"
}

t_main
