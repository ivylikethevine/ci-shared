#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Collects the outbound endpoints harden-runner recorded for a workflow's
# macOS and Windows jobs over its last successful runs, from StepSecurity's
# public run API (public repositories only), and prints one row per job and
# endpoint: how many of the runs saw it, the steps that called it, and whether
# only macOS or Windows system processes did (`os`), which an allowlist can
# usually leave out.
#
#   scratch/egress_baseline.sh <owner/repo> <workflow file> [runs=5] [label regex]
#
# A reusable workflow's jobs appear under the caller's runs, so name the
# caller. Matrix and shard numbers in job names are folded together. Needs
# gh, jq and curl, and network access to agent.api.stepsecurity.io; raw rows
# land in local/egress_baseline/<repo>-<workflow>.tsv.
set -euo pipefail
repo=$1 wf=$2 runs=${3:-5} labels=${4:-macos|windows}
here="$(dirname "$0")/.."
api="https://agent.api.stepsecurity.io/v1/github/$repo/actions/runs"
dir="$here/local/egress_baseline"
mkdir -p "$dir"
raw="$dir/${repo#*/}-${wf%.*}.tsv"
: >"$raw"

ids=$(gh run list -R "$repo" -w "$wf" -s success -L "$runs" --json databaseId --jq '.[].databaseId')
[[ -n $ids ]] || { echo "no successful $wf runs in $repo" >&2; exit 1; }
n=0
for id in $ids; do
	n=$((n + 1))
	curl -fsS -m 60 "$api/$id" | jq -r --arg id "$id" --arg labels "$labels" '
		(.jobs // [])[] | select(any(.labels[]?; test($labels; "i"))) as $j
		| ($j.name | gsub("(?<a>shard |\\()[0-9]+(/[0-9]+)?"; "\(.a)N")) as $job
		| ($j.steps // [])[] as $s | ($s.tools // [])[] as $t | ($t.endpoints // [])[]
		| [$id, $job, ($j.labels | join(",")), ($s.name | sub("^(Pre |Post )?Run "; "") | .[0:60]),
			$t.name, "\(.domainName // .ipAddress):\(.port)"] | @tsv' >>"$raw"
done

echo "# $repo $wf: $n runs, $(cut -f1 "$raw" | sort -u | wc -l) with macOS/Windows endpoint data"
jq -rRn --argjson total "$n" '
	[inputs | split("\t") | {run: .[0], job: .[1], label: .[2], step: .[3], proc: .[4], ep: .[5]}]
	| group_by([.job, .ep])[]
	| {job: .[0].job, label: .[0].label, ep: .[0].ep,
		runs: ([.[].run] | unique | length),
		os: all(.[]; .proc | test("^(/System/|/usr/libexec/|/usr/sbin/|/Library/Apple/|C:\\\\Windows\\\\|(svchost|firefox|pingsender)\\.exe$)"; "i")),
		steps: ([.[].step] | unique | join(" | "))}
	| [.job, .label, .ep, "\(.runs)/\($total)", (if .os then "os" else "" end), .steps] | @tsv' <"$raw" |
	sort -t$'\t' -k1,1 -k5,5 -k3,3 | column -t -s $'\t'
