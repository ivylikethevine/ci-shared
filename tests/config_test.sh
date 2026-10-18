#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/config.py: a valid repos/ prints as JSON with every optional key
# filled in; each kind of mistake prints its own line and nothing on stdout.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

config() {
  T_RC=0
  python3 -I "$SCRIPTS/config.py" "$T/tree" >"$T/out" 2>"$T/err" || T_RC=$?
}

test_fills_in_the_optional_keys() {
  echo x | t_shared a.txt
  t_target a-b main a.txt
  t_toml a-b <<'EOF'
[rulesets.main]
required_status_checks = [{ context = "ci" }, { context = "app", integration_id = 7 }]
EOF
  config
  t_rc 0
  t_eq "$(jq -c '.[0] | [.name, .token_secret, .templates, .rulesets.main]' "$T/out")" \
    '["a-b","SYNC_TOKEN_A_B",{},{"required_status_checks":[{"context":"ci","integration_id":15368},{"context":"app","integration_id":7}],"code_scanning_tools":[],"code_quality":false,"code_coverage":null}]' \
    "the filled-in config"
}

test_reports_every_mistake() {
  echo x | t_shared a
  cat >"$T/tree/repos/one.toml" <<'EOF'
repository = 5
sync_branch = "x"
files = "a"
templates = "x"
rulesets = "x"
extra = 1
EOF
  cat >"$T/tree/repos/two.toml" <<'EOF'
repository = "owner/other"
sync_branch = "dev"
files = ["a", "a", "missing"]
[templates]
b = "x"
[templates.a]
bad-key = "v"
repo = "x"
k = "50%"
[rulesets]
main = "x"
other = 1
EOF
  cat >"$T/tree/repos/three.toml" <<'EOF'
repository = "owner/three"
sync_branch = "dev"
[rulesets.main]
required_status_checks = "x"
code_scanning_tools = [1]
code_quality = "yes"
code_coverage = { minimum_coverage = 1 }
extra = 1
EOF
  cat >"$T/tree/repos/four.toml" <<'EOF'
repository = "owner/four"
sync_branch = "dev"
[rulesets.main]
required_status_checks = [{ context = 1 }]
EOF
  config
  t_rc 1
  [ ! -s "$T/out" ] || t_fail "stdout holds $(cat "$T/out")"
  t_in "$T/err" \
    "repos/one.toml: unknown key 'extra'" \
    "repos/one.toml: repository must be 'owner/name'" \
    "repos/one.toml: sync_branch must be one of main, dev" \
    "repos/one.toml: files must be a list of paths" \
    "repos/one.toml: templates must be a table" \
    "repos/one.toml: rulesets must be a table" \
    "repos/two.toml: repository 'owner/other' does not end in the file's name" \
    "repos/two.toml: a is listed twice" \
    "repos/two.toml: missing is listed but files/missing does not exist" \
    "repos/two.toml: templates.'b' is not in files" \
    "repos/two.toml: templates.'b' must be a table" \
    "repos/two.toml: templates.'a' key 'bad-key' is not letters and _" \
    "repos/two.toml: templates.'a'.repo is set by the sync, from the file's name" \
    "repos/two.toml: templates.'a'.k must be a string of single-spaced words without %, & or \\" \
    "repos/two.toml: rulesets: unknown key 'other'" \
    "repos/two.toml: rulesets.main must be a table" \
    "repos/three.toml: rulesets.main: unknown key 'extra'" \
    "repos/three.toml: rulesets.main.required_status_checks must be a list" \
    "repos/three.toml: rulesets.main.code_scanning_tools must be a list of names" \
    "repos/three.toml: rulesets.main.code_quality must be true or false" \
    "repos/three.toml: rulesets.main.code_coverage must set minimum_coverage and max_coverage_drop" \
    "repos/four.toml: each required status check is {context, integration_id}, not {'context': 1}"
}

test_an_empty_repos_fails() {
  config
  t_rc 1
  t_in "$T/err" "repos/ holds no <name>.toml"
}

t_main
