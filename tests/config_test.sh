#!/usr/bin/env bash
# scripts/config.py: a valid repos/ prints as JSON with every optional key
# filled in; each kind of mistake prints its own line and nothing on stdout.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# config [--self] - config.py over the tree, stdout in $T/out, stderr in $T/err
config() {
  T_RC=0
  python3 -I "$SCRIPTS/config.py" "$@" "$T/tree" >"$T/out" 2>"$T/err" || T_RC=$?
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
  t_eq "$(jq -c '.[0] | [.name, .token_secret, .templates, .immutable_releases, .rulesets.main]' "$T/out")" \
    '["a-b","SYNC_TOKEN_A_B",{},false,{"required_status_checks":[{"context":"ci","integration_id":15368},{"context":"app","integration_id":7}],"code_scanning_tools":[],"code_quality":false,"code_coverage":null}]' \
    "the filled-in config"
}

test_prints_its_own_entry_apart() {
  t_target a main
  config --self
  t_rc 0
  t_file "$T/out" null
  t_self own-repo <<'EOF'
immutable_releases = true
[rulesets.main]
required_status_checks = [{ context = "ci" }]
EOF
  config --self
  t_rc 0
  t_eq "$(jq -c '[.name, .token_secret, .immutable_releases, .rulesets.main.required_status_checks]' "$T/out")" \
    '["own-repo","SYNC_TOKEN_OWN_REPO",true,[{"context":"ci","integration_id":15368}]]' "this repository's entry"
  # no target
  config
  t_rc 0
  t_eq "$(jq -c '[.[].name]' "$T/out")" '["a"]' "the targets"
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
immutable_releases = "yes"
[rulesets.main]
required_status_checks = [{ context = 1 }]
EOF
  t_self four <<'EOF'
sync_branch = "dev"
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
    "repos/four.toml: each required status check is {context, integration_id}, not {'context': 1}" \
    "repos/four.toml: immutable_releases must be true or false" \
    "rulesets/self.toml: unknown key 'sync_branch'" \
    "rulesets/self.toml: its token secret SYNC_TOKEN_FOUR is also repos/four.toml's"
}

test_merges_the_base_list_and_keeps_values() {
  for f in a b c; do echo x | t_shared "$f"; done
  printf 'files = ["b", "a"]\n' >"$T/tree/repos/_base.toml"
  t_target one dev c
  printf 'base = true\nskip = ["b"]\n[values]\nlanguage = "python"\n' | t_toml one
  t_target two dev
  echo 'base = true' | t_toml two
  t_target three dev a
  config
  t_rc 0
  # _base.toml is no target; a target's files print sorted, base and skip gone
  t_eq "$(jq -c '[.[] | [.name, .files, .values, has("base"), has("skip")]]' "$T/out")" \
    '[["one",["a","c"],{"language":"python"},false,false],["three",["a"],{},false,false],["two",["a","b"],{},false,false]]' \
    "the merged files"
}

test_reports_base_and_values_mistakes() {
  echo x | t_shared a
  printf 'files = ["a", "a", "gone"]\n' >"$T/tree/repos/_base.toml"
  t_target one dev a
  printf 'base = true\nskip = ["b"]\n' | t_toml one
  t_target two dev
  printf 'base = "yes"\nskip = ["a"]\n' | t_toml two
  t_target three dev
  t_toml three <<'EOF'
skip = 1
[values]
bad-key = "v"
repo = "x"
k = "50%"
EOF
  t_target four dev
  echo 'values = "x"' | t_toml four
  t_target five dev a
  printf '[values]\nk = "v"\n[templates.a]\nk = "w"\n' | t_toml five
  config
  t_rc 1
  t_in "$T/err" \
    "repos/_base.toml: a is listed twice" \
    "repos/_base.toml: gone is listed but files/gone does not exist" \
    "repos/one.toml: a is in repos/_base.toml too" \
    "repos/one.toml: skip b is not in repos/_base.toml" \
    "repos/two.toml: base must be true or false" \
    "repos/two.toml: skip needs base = true" \
    "repos/three.toml: skip must be a list of paths" \
    "repos/three.toml: values key 'bad-key' is not letters and _" \
    "repos/three.toml: values.repo is set by the sync, from the file's name" \
    "repos/three.toml: values.k must be a string of single-spaced words without %, & or \\" \
    "repos/four.toml: values must be a table" \
    "repos/five.toml: templates.'a'.k is set in values too"
  # an unreadable base file fails the run too
  echo 'files = ' >"$T/tree/repos/_base.toml"
  config
  t_rc 1
  t_in "$T/err" "repos/_base.toml: "
}

test_reports_self_toml_mistakes() {
  t_target a main
  echo 'repository = "x"' >"$T/tree/rulesets/self.toml"
  config
  t_rc 1
  t_in "$T/err" "rulesets/self.toml: repository must be 'owner/name'"
  echo 'repository = ' >"$T/tree/rulesets/self.toml"
  config
  t_rc 1
  t_in "$T/err" "rulesets/self.toml: "
}

test_an_empty_repos_fails() {
  config
  t_rc 1
  t_in "$T/err" "repos/ holds no <name>.toml"
}

t_main
