#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check_protection.sh against a fake GitHub: it passes only targets
# whose main and dev are fully protected from the token, and fails closed on
# every API error, odd response, unknown bypass level, missing branch, missing
# token, invalid config and failed command, reading each target with its own
# token.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Ruleset 1 holds main, ruleset 2 holds dev; SCENARIO bends one answer at a
# time. $T/tokens.log gets "token endpoint" per call.
fake_github() {
  t_fake_gh <<'EOF'
s=${SCENARIO:-pass}
echo "${GH_TOKEN:-} $ep" >>"$T/tokens.log"
ruleset() {
  local id=$1 bypass=${2-never} enf=${3-active}
  [ "$s" != ruleset-id ] || id=99
  jq -n --argjson id "$id" --arg b "$bypass" --arg e "$enf" --arg s "$s" \
    '{id: $id, name: "r\($id)", enforcement: $e}
     + (if $s == "bypass-missing" then {} else {current_user_can_bypass: $b} end)'
}
case $ep in
*/git/matching-refs/heads/main)
  [ "$s" != refs-error ] || fail
  reply '[{"ref":"refs/heads/main"}]'
  ;;
*/git/matching-refs/heads/dev)
  [ "$s" != dev-missing ] || reply '[{"ref":"refs/heads/devel"}]'
  [ "$s" = dev-missing ] || reply '[{"ref":"refs/heads/dev"}]'
  ;;
*/rules/branches/main*)
  case $s in
  rules-error) fail ;;
  rules-object) reply '{"type":"pull_request","ruleset_id":1}' ;;
  rules-garbage) reply 'not json' ;;
  main-unprotected) reply '[{"type":"deletion","ruleset_id":1}]' ;;
  *) reply '[{"type":"pull_request","ruleset_id":1},{"type":"non_fast_forward","ruleset_id":1},{"type":"deletion","ruleset_id":1}]' ;;
  esac
  ;;
*/rules/branches/dev*)
  reply '[{"type":"required_signatures","ruleset_id":2},{"type":"non_fast_forward","ruleset_id":2},{"type":"deletion","ruleset_id":2}]'
  ;;
*/rulesets/1)
  [ "$s" != ruleset-error ] || fail "HTTP 404"
  case $s in
  bypass-always) reply "$(ruleset 1 always)" ;;
  bypass-unknown) reply "$(ruleset 1 sometimes)" ;;
  evaluate) reply "$(ruleset 1 never evaluate)" ;;
  *) reply "$(ruleset 1)" ;;
  esac
  ;;
*/rulesets/2) reply "$(ruleset 2 pull_requests_only)" ;;
*) fail "unexpected $ep" ;;
esac
EOF
}

# check <0|1> [scenario] - one run against owner/repo on dev
check() {
  t_run env SCENARIO="${2:-pass}" GH_TOKEN=fake "$SCRIPTS/check_protection.sh"
  t_rc "$1"
}

test_passes_a_fully_protected_target() {
  fake_github
  t_target repo dev
  check 0
  t_out "owner/repo main: protected" "owner/repo dev: protected"
  t_target repo main
  check 0
}

test_fails_each_bent_answer() {
  local s
  fake_github
  t_target repo dev
  for s in bypass-always bypass-unknown bypass-missing evaluate rules-error \
    rules-object rules-garbage ruleset-error ruleset-id dev-missing refs-error; do
    check 1 "$s"
  done
}

test_names_what_is_missing_and_what_did_not_count() {
  fake_github
  t_target repo dev
  check 1 bypass-always
  t_out "::error title=protection owner/repo main::lacks non_fast_forward, deletion, pull_request; not counted: r1 (active, bypass always)"
  check 1 main-unprotected
  t_out "lacks non_fast_forward, pull_request"
  check 1 ruleset-error
  t_out "cannot read ruleset 1"
  check 1 rules-error
  t_out "cannot read its rules"
  check 1 rules-object
  t_out "unexpected rules response"
  check 1 dev-missing
  t_out "owner/repo dev::no such branch"
  check 1 refs-error
  t_out "cannot list its refs"
}

test_fails_without_a_token() {
  fake_github
  t_target repo dev
  t_run "$SCRIPTS/check_protection.sh"
  t_rc 1
  t_out "::error title=protection owner/repo::no token: SYNC_TOKEN_REPO is not set"
  t_not_logged .
}

test_reads_each_target_with_its_own_token() {
  fake_github
  t_target repo dev
  t_target other-repo dev
  t_run env GH_TOKEN=shared SYNC_TOKEN_REPO=own "$SCRIPTS/check_protection.sh"
  t_rc 0
  t_eq "$(cut -d' ' -f1 "$T/tokens.log" | sort -u | tr '\n' ' ')" "own shared " "the tokens used"
  t_in "$T/tokens.log" 'own repos/owner/repo/'
  t_not_in "$T/tokens.log" 'own repos/owner/other-repo/'
  : >"$T/tokens.log"
  t_run env SYNC_TOKEN_OTHER_REPO=o "$SCRIPTS/check_protection.sh" other-repo
  t_rc 0
  t_out "owner/other-repo dev: protected"
  t_no_out "owner/repo "
  t_run env GH_TOKEN=t "$SCRIPTS/check_protection.sh" nope
  t_rc 1
  t_out "repos/ has no target nope"
}

test_fails_on_an_invalid_config() {
  local c
  fake_github
  for c in 'repository = "not-a-slug"' 'repository = "owner/other"' \
    'repository = "owner/repo"' 'repository = "owner/repo
sync_branch = "release"' 'repository = "owner/repo' 'repository = "owner/repo
sync_branch = "dev"
extra = 1' 'repository = "owner/repo
sync_branch = "dev"
files = ["nope"]'; do
    rm -f "$T/tree/repos/"*.toml
    printf '%s\n' "$c" >"$T/tree/repos/repo.toml"
    check 1
  done
  rm "$T/tree/repos/repo.toml"
  check 1
  t_out "repos/ holds no <name>.toml"
  t_target repo dev
  t_target repo2 release
  check 1
  rm "$T/tree/repos/repo2.toml"
  t_target repo-2 dev
  t_target repo_2 dev
  check 1
  t_out "repos/repo_2.toml: its token secret SYNC_TOKEN_REPO_2 is also repos/repo-2.toml's"
  t_not_logged .
}

# Rows config.py would refuse, and an empty list, through a stand-in for it:
# the check does not lean on config.py alone for what it lets the sync write.
test_refuses_rows_config_py_would_have() {
  fake_github
  t_fake python3 <<'EOF'
#!/usr/bin/env bash
cat "$T/config.json"
EOF
  echo '[]' >"$T/config.json"
  check 1
  t_out "repos/ lists no targets"
  jq -n '[{name: "repo", token_secret: "SYNC_TOKEN_REPO", repository: "owner/repo", sync_branch: "dev"},
    {repository: "not a slug", sync_branch: "dev"},
    {repository: "owner/x", sync_branch: "dev extra"},
    {repository: "owner/y", sync_branch: "release"}]' >"$T/config.json"
  check 1
  t_out "owner/repo dev: protected" \
    "target 'not a slug dev' is not 'owner/name main|dev'" \
    "target 'owner/x dev extra' is not" "target 'owner/y release' is not"
}

# A jq that fails where its pattern matches the program, the real one
# otherwise: a command failing mid-check fails the branch.
test_fails_closed_when_a_command_fails() {
  local real
  real="$(command -v jq)"
  fake_github
  t_target repo dev
  t_fake jq <<EOF
#!/usr/bin/env bash
case "\$*" in *"\$JQ_FAIL"*) [ -z "\$JQ_FAIL" ] || exit 5 ;; esac
exec "$real" "\$@"
EOF
  # shellcheck disable=SC2016 # literal text
  t_run env JQ_FAIL='$h + [' GH_TOKEN=fake "$SCRIPTS/check_protection.sh"
  t_rc 1
  t_out "cannot read ruleset 1's rules"
  t_run env JQ_FAIL='join(" or ")' GH_TOKEN=fake "$SCRIPTS/check_protection.sh"
  t_rc 1
  t_out "cannot compare its rules"
}

t_main
