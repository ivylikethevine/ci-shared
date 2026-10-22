#!/usr/bin/env bash
# scripts/sync_prs.sh against a fake GitHub: each target's open sync pull
# request with its age and checks, failing one with a failed check, no checks
# or too great an age, and one it cannot read, each with its own token.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# a's pull request is AGE days old (default 2); CHECKS and STATUSES are its
# check runs and commit statuses as JSON lists; b has none open. A *_ERROR
# fails that read. $T/tokens.log gets "token endpoint" per call.
fake_github() {
  t_fake_gh <<'EOF'
echo "${GH_TOKEN:-} $ep" >>"$T/tokens.log"
case $ep in
repos/owner/a/pulls\?head=owner:ci-sync\&base=dev\&state=open)
  [ -z "${PULLS_ERROR:-}" ] || fail
  reply "$(jq -n --arg c "$(date -u -d "${AGE:-2} days ago" +%Y-%m-%dT%H:%M:%SZ)" \
    '[{number: 7, html_url: "https://github.com/owner/a/pull/7", head: {sha: "abc"}, created_at: $c}]')"
  ;;
repos/owner/b/pulls\?head=owner:ci-sync\&base=main\&state=open) reply '[]' ;;
repos/owner/a/commits/abc/check-runs\?per_page=100)
  [ -z "${RUNS_ERROR:-}" ] || fail "HTTP 403"
  reply "{\"check_runs\": ${CHECKS:-[]}}"
  ;;
repos/owner/a/commits/abc/status)
  [ -z "${STATUS_ERROR:-}" ] || fail "HTTP 403"
  reply "{\"statuses\": ${STATUSES:-[]}}"
  ;;
*) fail "unexpected $ep" ;;
esac
EOF
}

fixture() {
  t_target a dev
  t_target b main
  fake_github
}

PASSING='[{"name":"lint","status":"completed","conclusion":"success"},
  {"name":"docs","status":"completed","conclusion":"skipped"},
  {"name":"e2e","status":"in_progress","conclusion":null}]'

test_reports_each_target() {
  fixture
  t_run env GH_TOKEN=t CHECKS="$PASSING" STATUSES='[{"context":"ci/x","state":"success"}]' \
    GITHUB_STEP_SUMMARY="$T/summary" "$SCRIPTS/sync_prs.sh"
  t_rc 0
  t_out "a: #7 into dev, open 2 days: 3 passed, 0 failed, 1 pending" "b: no sync pull request open"
  t_in -x "$T/summary" "## Sync pull requests" "| a | [#7](https://github.com/owner/a/pull/7) | 2 days | 3 | 0 | 1 |" \
    "| b | none open | | | | |"
}

test_fails_a_failed_check_naming_it() {
  fixture
  t_run env GH_TOKEN=t CHECKS='[{"name":"lint","status":"completed","conclusion":"failure"},
    {"name":"build","status":"completed","conclusion":"timed_out"}]' \
    STATUSES='[{"context":"ci/x","state":"error"},{"context":"ci/y","state":"pending"}]' "$SCRIPTS/sync_prs.sh" a
  t_rc 1
  t_out "a: #7 into dev, open 2 days: 0 passed, 3 failed (lint, build, ci/x), 1 pending" \
    "a: #7 has a failed check" "::error title=sync pull request a::"
  t_not_logged owner/b
}

test_fails_a_pull_request_with_no_checks() {
  fixture
  t_run env GH_TOKEN=t "$SCRIPTS/sync_prs.sh" a
  t_rc 1
  t_out "a: #7 into dev, open 2 days: 0 passed, 0 failed, 0 pending" "a: #7 has no checks"
}

test_fails_a_stale_pull_request() {
  fixture
  t_run env GH_TOKEN=t AGE=14 CHECKS="$PASSING" "$SCRIPTS/sync_prs.sh" a
  t_rc 0
  t_run env GH_TOKEN=t AGE=15 CHECKS="$PASSING" "$SCRIPTS/sync_prs.sh" a
  t_rc 1
  t_out "a: #7 has been open more than 14 days"
}

test_fails_each_read_it_cannot_make() {
  fixture
  t_run env GH_TOKEN=t PULLS_ERROR=1 "$SCRIPTS/sync_prs.sh"
  t_rc 1
  t_out "a: cannot list its pull requests" "b: no sync pull request open"
  t_run env GH_TOKEN=t RUNS_ERROR=1 "$SCRIPTS/sync_prs.sh" a
  t_rc 1
  t_out "a: cannot read the check runs on #7 (the token needs Checks read)"
  t_run env GH_TOKEN=t CHECKS="$PASSING" STATUS_ERROR=1 "$SCRIPTS/sync_prs.sh" a
  t_rc 1
  t_out "a: cannot read the commit statuses on #7 (the token needs Commit statuses read)"
}

test_reads_each_target_with_its_own_token() {
  fixture
  t_run env GH_TOKEN=shared SYNC_TOKEN_A=own CHECKS="$PASSING" "$SCRIPTS/sync_prs.sh"
  t_rc 0
  t_in "$T/tokens.log" "own repos/owner/a/commits/abc/status" "shared repos/owner/b/pulls?head=owner:ci-sync&base=main&state=open"
  t_not_in "$T/tokens.log" "shared repos/owner/a/" "own repos/owner/b/"
  t_run env SYNC_TOKEN_A=own CHECKS="$PASSING" "$SCRIPTS/sync_prs.sh"
  t_rc 1
  t_out "no token: SYNC_TOKEN_B is not set" "::error title=sync pull request b::"
  t_run env GH_TOKEN=t "$SCRIPTS/sync_prs.sh" nope
  t_rc 1
  t_out "repos/ has no target nope"
}

t_main
