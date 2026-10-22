#!/usr/bin/env bash
# Reports each target's open sync pull request: its age and the checks on its
# head, so a shared file that breaks a target shows up here. Fails a target
# whose pull request has a failed check, has no checks, or has been open more
# than STALE_DAYS; a target with none open passes.
#
#   SYNC_TOKEN_<NAME>=<token>... scripts/sync_prs.sh [NAME...]
#   GH_TOKEN=<token> scripts/sync_prs.sh [NAME...]
#
# Each target is read with its own SYNC_TOKEN_<NAME>, else with GH_TOKEN, which
# needs Pull requests, Checks and Commit statuses read on it. NAME limits the
# report to those targets. Exits with the number of targets that fail. When
# GITHUB_STEP_SUMMARY is set (an Actions job), a table row per target is
# appended to it.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

BRANCH=ci-sync
STALE_DAYS=14
# the fields report reads from the open sync pull request
PR_FIELDS='.[0] | select(. != null) | "\(.number) \(.html_url) \(.head.sha) \(.created_at)"'

repos="$(ci_repos "$@")"

summary() {
  printf '%s\n' "$@" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}
summary '## Sync pull requests' '' '| Target | Pull request | Open | Passed | Failed | Pending |' '| --- | --- | --- | --- | --- | --- |'

# report <slug> <base> - prints the target's line, and fails when the pull
# request needs a look
report() {
  local slug=$1 base=$2 name=${1#*/} pr number url sha created days checks passed failed pending names
  pr="$(gh api "repos/$slug/pulls?head=${slug%%/*}:$BRANCH&base=$base&state=open" --jq "$PR_FIELDS")" || {
    echo "$name: cannot list its pull requests"
    return 1
  }
  if [ -z "$pr" ]; then
    echo "$name: no sync pull request open"
    summary "| $name | none open | | | | |"
    return 0
  fi
  read -r number url sha created <<<"$pr"
  days=$((($(date +%s) - $(date -d "$created" +%s)) / 86400))
  # one "<state> <name>" line per check run and commit status, state being
  # passed, failed or pending
  checks="$(gh api --paginate "repos/$slug/commits/$sha/check-runs?per_page=100" --jq '.check_runs[]
    | "\(if .status != "completed" then "pending"
         elif .conclusion | IN("success", "neutral", "skipped") then "passed"
         else "failed" end) \(.name)"')" || {
    echo "$name: cannot read the check runs on #$number (the token needs Checks read)"
    return 1
  }
  checks="$checks"$'\n'"$(gh api "repos/$slug/commits/$sha/status" --jq '.statuses[]
    | "\({success: "passed", pending: "pending"}[.state] // "failed") \(.context)"')" || {
    echo "$name: cannot read the commit statuses on #$number (the token needs Commit statuses read)"
    return 1
  }
  passed="$(grep -c '^passed ' <<<"$checks" || true)"
  failed="$(grep -c '^failed ' <<<"$checks" || true)"
  pending="$(grep -c '^pending ' <<<"$checks" || true)"
  names="$(sed -n 's/^failed //p' <<<"$checks" | paste -sd, - | sed 's/,/, /g')"
  echo "$name: #$number into $base, open $days days: $passed passed, $failed failed${names:+ ($names)}, $pending pending"
  summary "| $name | [#$number]($url) | $days days | $passed | $failed${names:+ ($names)} | $pending |"
  if [ "$failed" -gt 0 ]; then
    echo "$name: #$number has a failed check"
    return 1
  fi
  if [ $((passed + pending)) = 0 ]; then
    echo "$name: #$number has no checks"
    return 1
  fi
  if [ "$days" -gt "$STALE_DAYS" ]; then
    echo "$name: #$number has been open more than $STALE_DAYS days"
    return 1
  fi
}

failed=0
while read -r slug base; do
  name="${slug#*/}"
  # set -e turned back on inside a subshell outside any `if` or `||` (it
  # inherits the +e), so a failure stops this target alone
  set +e
  (
    set -e
    GH_TOKEN="$(ci_token "$name")"
    export GH_TOKEN
    report "$slug" "$base"
  )
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "::error title=sync pull request $name::see the lines above"
    failed=$((failed + 1))
  fi
done <<<"$repos"

exit "$failed"
