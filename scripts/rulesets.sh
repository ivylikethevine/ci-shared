#!/usr/bin/env bash
# Renders the shared branch rulesets for a target, or compares them with the
# ones live on GitHub. rulesets/main.json and rulesets/dev.json hold what every
# target shares; the [rulesets.main] table of repos/<name>.toml holds the values
# that are its own on main: the required status checks, the code scanning
# tools, the coverage floor and whether code quality is gated.
#
#   scripts/rulesets.sh render NAME main|dev
#   GH_TOKEN=<token> scripts/rulesets.sh diff [NAME...]
#
# `render` prints JSON that GitHub's ruleset import takes (Settings → Rules →
# Rulesets → New ruleset → Import a ruleset). `diff` prints a unified diff per
# ruleset that differs, reads only, and exits with the number that differ or
# could not be read.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

DIR="$CI_SHARED_DIR/rulesets"

render() {
  local name=$1 kind=$2 values
  case $kind in
  dev) cat "$DIR/dev.json" ;;
  main)
    values="$(ci_ruleset_values "$name")" || return 1
    jq --argjson m "$values" '
        [$m.code_scanning_tools[] | {tool: ., alerts_threshold: "errors",
            security_alerts_threshold: "high_or_higher"}] as $tools
        | .rules |= map(if .type == "required_status_checks"
            then .parameters.required_status_checks = $m.required_status_checks
            else . end)
        | .rules += (if $tools == [] then []
            else [{type: "code_scanning", parameters: {code_scanning_tools: $tools}}] end)
        | .rules += (if $m.code_coverage
            then [{type: "code_coverage", parameters: $m.code_coverage}] else [] end)
        | .rules += (if $m.code_quality
            then [{type: "code_quality", parameters: {severity: "errors"}}] else [] end)
      ' "$DIR/main.json"
    ;;
  *)
    echo "unknown ruleset $kind: main or dev" >&2
    return 2
    ;;
  esac
}

# Drops what GitHub adds and puts lists in one order, so a rendered ruleset and
# a live one compare equal when they hold the same rules.
normalize() {
  jq -S '
    del(.id, .node_id, .source, .source_type, ._links, .created_at, .updated_at,
      .current_user_can_bypass)
    | .bypass_actors |= sort_by(.actor_type, .actor_id)
    | .rules |= (sort_by(.type) | map(
        if .parameters.required_status_checks then .parameters.required_status_checks |= sort_by(.context) else . end
        | if .parameters.code_scanning_tools then .parameters.code_scanning_tools |= sort_by(.tool) else . end
        | if .parameters.allowed_merge_methods then .parameters.allowed_merge_methods |= sort else . end))'
}

diff_repo() {
  local slug=$1 name=${1#*/} kind want id differs=0
  for kind in main dev; do
    want="$(render "$name" "$kind" | normalize)"
    id="$(gh api "repos/$slug/rulesets?includes_parents=false" |
      jq -r --arg n "$(jq -r .name <<<"$want")" '.[] | select(.name == $n) | .id')"
    if [ -z "$id" ]; then
      echo "$name: no $(jq -r .name <<<"$want") ruleset"
      differs=$((differs + 1))
      continue
    fi
    if ! diff -u --label "$name $kind (live)" --label "$name $kind (shared)" \
      <(gh api "repos/$slug/rulesets/$id" | normalize) <(echo "$want"); then
      differs=$((differs + 1))
    fi
  done
  return "$differs"
}

case ${1:-} in
render)
  [ $# = 3 ] || {
    echo "usage: $0 render NAME main|dev" >&2
    exit 2
  }
  render "$2" "$3"
  ;;
diff)
  shift
  failed=0
  while read -r slug _; do
    name="${slug#*/}"
    if [ $# -gt 0 ]; then
      wanted=0
      for n in "$@"; do [ "$n" = "$name" ] && wanted=1; done
      [ "$wanted" = 1 ] || continue
    fi
    # a subshell outside any `if`, so `set -e` stops this repository alone
    set +e
    (diff_repo "$slug")
    rc=$?
    set -e
    failed=$((failed + rc))
  done < <(ci_repos)
  exit "$failed"
  ;;
*)
  echo "usage: $0 render NAME main|dev | diff [NAME...]" >&2
  exit 2
  ;;
esac
