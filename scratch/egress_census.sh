#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Lists every workflow job in the checkouts beside this repository that runs
# on macOS or Windows, with its harden-runner egress policy and the number of
# allowed endpoints, as TSV: repo, workflow, job, runners, policy, endpoints.
# A runner read from the matrix is matched against every matrix value.
#
#   scratch/egress_census.sh [repo...]   # default: every repos/*.toml target
#
# Needs bash, jq and mikefarah yq; output also lands in local/egress_census.tsv.
set -euo pipefail
here="${CI_SHARED_DIR:-$(dirname "$0")/..}"
if (($# == 0)); then
  for f in "$here"/repos/*.toml; do set -- "$@" "$(basename "$f" .toml)"; done
fi
mkdir -p "$here/local"
out="$here/local/egress_census.tsv"
printf 'repo\tworkflow\tjob\trunners\tpolicy\tendpoints\n' >"$out"
for repo in "$@"; do
  for wf in "$here/../$repo"/.github/workflows/*.y*ml; do
    [[ -f $wf ]] || continue
    yq -o=json '.' "$wf" | jq -r --arg repo "$repo" --arg wf "$(basename "$wf")" '
			(.jobs // {}) | to_entries[] | .key as $job | .value as $j
			| ([$j["runs-on"]] + [$j.strategy.matrix // {} | .. | strings]
				| map(select(type == "string" and test("macos|windows"; "i"))) | unique) as $os
			| select($os | length > 0)
			| [$j.steps // [] | .[] | select((.uses // "") | test("harden-runner"))] as $hs
			| [$repo, $wf, $job, ($os | join(",")),
				(if $hs == [] then "none" else $hs | map(
					(.with["egress-policy"] // "audit")
					+ (if .if then " [if " + (.if | tostring) + "]" else "" end)) | join("; ") end),
				($hs | map((.with["allowed-endpoints"] // "") | [splits("\\s+")]
					| map(select(. != "")) | length | tostring) | join("; "))]
			| @tsv'
  done
done >>"$out"
column -t -s $'\t' "$out"
