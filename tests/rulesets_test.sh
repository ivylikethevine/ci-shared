#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/rulesets.sh: renders the shared rulesets with a target's own values,
# and diffs them against a fake GitHub's live ones.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# a with every optional rule, b with none
fixture() {
  t_target a dev
  t_toml a <<'EOF'
[rulesets.main]
required_status_checks = [{ context = "tests", integration_id = 1 }]
code_scanning_tools = ["CodeQL"]
code_quality = true
code_coverage = { minimum_coverage = 80, max_coverage_drop = 2 }
EOF
  t_target b dev
}

test_render_main_adds_each_target_value() {
  fixture
  t_run "$SCRIPTS/rulesets.sh" render a main
  t_rc 0
  t_eq "$(jq -c '[.rules[].type]' "$T/out")" \
    '["deletion","non_fast_forward","required_signatures","pull_request","required_status_checks","code_scanning","code_coverage","code_quality"]' "a's rules"
  t_eq "$(jq -c '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks' "$T/out")" \
    '[{"context":"tests","integration_id":1}]' "a's checks"
  t_eq "$(jq -c '.rules[] | select(.type == "code_coverage") | .parameters' "$T/out")" \
    '{"minimum_coverage":80,"max_coverage_drop":2}' "a's coverage"
  t_run "$SCRIPTS/rulesets.sh" render b main
  t_rc 0
  t_eq "$(jq -c '[.rules[].type]' "$T/out")" \
    '["deletion","non_fast_forward","required_signatures","pull_request","required_status_checks"]' "b's rules"
}

test_render_dev_and_stable_are_the_shared_files() {
  local kind
  fixture
  for kind in dev stable; do
    t_run "$SCRIPTS/rulesets.sh" render a "$kind"
    t_rc 0
    cmp -s "$T/out" "$REPO_DIR/rulesets/$kind.json" || t_fail "$kind differs from rulesets/$kind.json"
  done
}

test_render_refuses_bad_arguments() {
  fixture
  t_run "$SCRIPTS/rulesets.sh" render a release
  t_rc 2
  t_out "unknown ruleset release: main, dev or stable"
  t_run "$SCRIPTS/rulesets.sh" render a
  t_rc 2
  t_out "usage: "
  t_run "$SCRIPTS/rulesets.sh" render nobody main
  t_rc 1
  t_run "$SCRIPTS/rulesets.sh"
  t_rc 2
  t_out "render NAME main|dev|stable | diff [NAME...]"
}

# The live rulesets are a's, rendered and dressed as GitHub returns them, with
# DRIFT changing one rule, MISSING dropping dev's, HIDDEN leaving out main's
# bypass_actors as GitHub does for a token that cannot edit it, and READ_ERROR
# failing stable's read. $T/tokens.log gets "token endpoint" per call.
fake_github() {
  local kind id=0
  for kind in main dev stable; do
    id=$((id + 1))
    "$SCRIPTS/rulesets.sh" render a "$kind" | jq --argjson id "$id" '
      . + {id: $id, node_id: "x", source: "owner/a",
        source_type: "Repository", _links: {}, created_at: "t", updated_at: "t",
        current_user_can_bypass: "never"}
      | .rules |= reverse | .conditions.ref_name.include |= reverse' >"$T/live-$kind.json"
  done
  t_fake_gh <<'EOF'
echo "${GH_TOKEN:-} $ep" >>"$T/tokens.log"
case $ep in
*/rulesets\?includes_parents=false)
  [ -z "${LIST_ERROR:-}" ] || fail
  [ -n "${MISSING:-}" ] || reply '[{"id":1,"name":"protect-main"},{"id":2,"name":"protect-dev"},{"id":3,"name":"protect-stable"}]'
  [ -z "${MISSING:-}" ] || reply '[{"id":1,"name":"protect-main"},{"id":3,"name":"protect-stable"}]'
  ;;
*/rulesets/1)
  if [ -n "${DRIFT:-}" ]; then
    jq '.rules |= map(select(.type != "code_quality"))' "$T/live-main.json"
  elif [ -n "${HIDDEN:-}" ]; then
    jq 'del(.bypass_actors)' "$T/live-main.json"
  else
    cat "$T/live-main.json"
  fi
  ;;
*/rulesets/2) cat "$T/live-dev.json" ;;
*/rulesets/3)
  [ -z "${READ_ERROR:-}" ] || fail
  cat "$T/live-stable.json"
  ;;
*) fail "unexpected $ep" ;;
esac
EOF
}

test_diff_matches_rulesets_as_github_returns_them() {
  fixture
  fake_github
  t_run env GH_TOKEN=t "$SCRIPTS/rulesets.sh" diff a
  t_rc 0
  t_not_logged owner/b
  t_run env GH_TOKEN=t "$SCRIPTS/rulesets.sh" diff nope
  t_rc 1
  t_out "repos/ has no target nope"
}

test_diff_shows_drift_and_missing_rulesets() {
  fixture
  fake_github
  t_run env GH_TOKEN=t DRIFT=1 MISSING=1 "$SCRIPTS/rulesets.sh" diff a
  t_rc 2
  t_out "--- a main (live)" "+++ a main (shared)" '"type": "code_quality"' "a: no protect-dev ruleset"
}

test_diff_compares_hidden_bypass_actors_without_them() {
  fixture
  fake_github
  t_run env GH_TOKEN=t HIDDEN=1 "$SCRIPTS/rulesets.sh" diff a
  t_rc 0
  t_out "a main: bypass_actors hidden from this token; compared without them"
  t_no_out "a dev: bypass_actors hidden"
  t_run env GH_TOKEN=t HIDDEN=1 DRIFT=1 "$SCRIPTS/rulesets.sh" diff a
  t_rc 1
  t_out '"type": "code_quality"'
}

test_diff_counts_a_ruleset_it_cannot_read() {
  fixture
  fake_github
  t_run env GH_TOKEN=t READ_ERROR=1 "$SCRIPTS/rulesets.sh" diff a
  t_rc 1
  t_out "a: cannot read its protect-stable ruleset"
}

test_diff_reads_each_target_with_its_own_token() {
  fixture
  fake_github
  t_run env GH_TOKEN=shared SYNC_TOKEN_A=own "$SCRIPTS/rulesets.sh" diff
  t_in "$T/tokens.log" "own repos/owner/a/rulesets?includes_parents=false" "shared repos/owner/b/rulesets?includes_parents=false"
  t_not_in "$T/tokens.log" "shared repos/owner/a/" "own repos/owner/b/"
  t_run env SYNC_TOKEN_A=own "$SCRIPTS/rulesets.sh" diff
  t_rc 1
  t_out "no token: SYNC_TOKEN_B is not set"
}

test_diff_counts_each_target_it_cannot_read() {
  fixture
  fake_github
  t_run env GH_TOKEN=t LIST_ERROR=1 "$SCRIPTS/rulesets.sh" diff
  t_rc 2
  t_out "a: cannot list its rulesets" "b: cannot list its rulesets"
}

t_main
