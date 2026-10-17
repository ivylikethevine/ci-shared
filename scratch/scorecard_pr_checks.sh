#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Replays Scorecard's CI-Tests and SAST probes over a target's last 30 commits
# on main: for each commit merged through a pull request, lists the check runs
# on the PR's head commit and says whether a successful github-actions run
# (CI-Tests) and a successful github-advanced-security run, the CodeQL result (SAST), was among them,
# as TSV: repo, sha, pr, merged, title, ci, sast, check names.
#
#   scratch/scorecard_pr_checks.sh [repo...]   # default: every repos/*.toml target
#
# Needs gh (a read token) and jq; output also lands in local/scorecard_pr_checks.tsv.
set -euo pipefail
here="$(dirname "$0")/.."
if (($# == 0)); then
  for f in "$here"/repos/*.toml; do set -- "$@" "$(basename "$f" .toml)"; done
fi
mkdir -p "$here/local"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/scorecard_pr_checks.XXXXXX")"
trap '[[ $tmp == */scorecard_pr_checks.?????? ]] && rm -r -- "$tmp"' EXIT
out="$here/local/scorecard_pr_checks.tsv"
printf 'repo\tsha\tpr\tmerged\ttitle\tci\tsast\tchecks\n' >"$out"
for repo in "$@"; do
  slug="$(sed -n 's/^repository *= *"\(.*\)"/\1/p' "$here/repos/$repo.toml")"
  gh api "repos/$slug/commits?sha=main&per_page=30" --jq '.[].sha' | while read -r sha; do
    pr="$(gh api "repos/$slug/commits/$sha/pulls" --jq '[.[] | select(.merged_at != null)][0] // empty')"
    [[ -n $pr ]] || continue
    head="$(jq -r .head.sha <<<"$pr")"
    gh api --paginate "repos/$slug/commits/$head/check-runs?per_page=100" --jq '.check_runs[]' |
      jq -s '.' >"$tmp/runs.json"
    jq -n -r --arg repo "$repo" --arg sha "${sha:0:8}" --argjson pr "$pr" --slurpfile r "$tmp/runs.json" '
			$r[0] as $runs |
			def ok(slug): [$runs[] | select(.app.slug == slug and .status == "completed" and .conclusion == "success")] | length > 0;
			[$repo, $sha, ($pr.number | tostring), ($pr.merged_at[0:10]), ($pr.title[0:50]),
				(if ok("github-actions") then "yes" else "NO" end),
				(if ok("github-advanced-security") then "yes" else "NO" end),
				([$runs[] | "\(.app.slug):\(.name)=\(.conclusion)"] | unique | join(" "))]
			| @tsv'
  done
done >>"$out"
column -t -s $'\t' "$out" | cut -c1-200
