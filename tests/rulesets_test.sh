#!/usr/bin/env bash
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

test_render_dev_is_the_shared_file() {
  fixture
  t_run "$SCRIPTS/rulesets.sh" render a dev
  t_rc 0
  cmp -s "$T/out" "$REPO_DIR/rulesets/dev.json" || t_fail "dev differs from rulesets/dev.json"
}

test_render_refuses_bad_arguments() {
  fixture
  t_run "$SCRIPTS/rulesets.sh" render a release
  t_rc 2
  t_out "unknown ruleset release: main or dev"
  t_run "$SCRIPTS/rulesets.sh" render a
  t_rc 2
  t_out "usage: "
  t_run "$SCRIPTS/rulesets.sh" render nobody main
  t_rc 1
  t_run "$SCRIPTS/rulesets.sh"
  t_rc 2
  t_out "render NAME main|dev | diff [NAME...]"
}

# The live rulesets are a's, rendered and dressed as GitHub returns them, with
# DRIFT changing one rule and MISSING dropping dev's.
fake_github() {
  local kind
  for kind in main dev; do
    "$SCRIPTS/rulesets.sh" render a "$kind" | jq --arg k "$kind" '
      . + {id: (if $k == "main" then 1 else 2 end), node_id: "x", source: "owner/a",
        source_type: "Repository", _links: {}, created_at: "t", updated_at: "t",
        current_user_can_bypass: "never"}
      | .rules |= reverse' >"$T/live-$kind.json"
  done
  t_fake_gh <<'EOF'
case $ep in
*/rulesets\?includes_parents=false)
  [ -z "${LIST_ERROR:-}" ] || fail
  [ -n "${MISSING:-}" ] || reply '[{"id":1,"name":"protect-main"},{"id":2,"name":"protect-dev"}]'
  [ -z "${MISSING:-}" ] || reply '[{"id":1,"name":"protect-main"}]'
  ;;
*/rulesets/1)
  if [ -n "${DRIFT:-}" ]; then
    jq '.rules |= map(select(.type != "code_quality"))' "$T/live-main.json"
  else
    cat "$T/live-main.json"
  fi
  ;;
*/rulesets/2) cat "$T/live-dev.json" ;;
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
}

test_diff_shows_drift_and_missing_rulesets() {
  fixture
  fake_github
  t_run env GH_TOKEN=t DRIFT=1 MISSING=1 "$SCRIPTS/rulesets.sh" diff a
  t_rc 2
  t_out "--- a main (live)" "+++ a main (shared)" '"type": "code_quality"' "a: no protect-dev ruleset"
}

test_diff_counts_each_target_it_cannot_read() {
  fixture
  fake_github
  t_run env GH_TOKEN=t LIST_ERROR=1 "$SCRIPTS/rulesets.sh" diff
  t_rc 2
  t_out "a: cannot list its rulesets" "b: cannot list its rulesets"
}

t_main
