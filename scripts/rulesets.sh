#!/usr/bin/env bash
# Renders the shared rulesets for a target, or compares them with the ones live
# on GitHub. rulesets/main.json, dev.json and stable.json (the v* and *-rc tags)
# hold what every target shares; the [rulesets.main] table of repos/<name>.toml
# holds the values that are its own on main: the required status checks, the
# code scanning tools, the coverage floor and whether code quality is gated.
# rulesets/self.toml gives this repository's own, for its main alone.
#
#   scripts/rulesets.sh render NAME main|dev|stable
#   SYNC_TOKEN_<NAME>=<token>... scripts/rulesets.sh diff [NAME...]
#   GH_TOKEN=<token> scripts/rulesets.sh diff [NAME...]
#
# `render` prints JSON that GitHub's ruleset import takes (Settings → Rules →
# Rulesets → New ruleset → Import a ruleset). `diff` prints a unified diff per
# ruleset that differs, then two settings beside them: actions pinned to a
# full-length commit SHA (every repository) and immutable releases (where
# immutable_releases is true). It reads only, and exits with the number that
# differ or could not be read. Each repository is read with its own
# SYNC_TOKEN_<NAME>, else with GH_TOKEN. GitHub returns a ruleset's
# bypass_actors, and either setting, only to a token with Administration read,
# so what is hidden is left out of the comparison, and named.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load
ci_load_self

DIR="$CI_SHARED_DIR/rulesets"

render() {
  local name=$1 kind=$2 values
  case $kind in
  dev | stable) cat "$DIR/$kind.json" ;;
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
    echo "unknown ruleset $kind: main, dev or stable" >&2
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
    | if has("bypass_actors") then .bypass_actors |= sort_by(.actor_type, .actor_id) else . end
    | .conditions.ref_name |= with_entries(.value |= sort)
    | .rules |= (sort_by(.type) | map(
        if .parameters.required_status_checks then .parameters.required_status_checks |= sort_by(.context) else . end
        | if .parameters.code_scanning_tools then .parameters.code_scanning_tools |= sort_by(.tool) else . end
        | if .parameters.allowed_merge_methods then .parameters.allowed_merge_methods |= sort else . end))'
}

# diff_repo <slug> <kind...> - compares those rulesets and the settings
diff_repo() {
  local slug=$1 name=${1#*/} kind want live title id got out differs=0
  shift
  live="$(gh api "repos/$slug/rulesets?includes_parents=false")" || {
    echo "$name: cannot list its rulesets"
    return 1
  }
  for kind; do
    want="$(render "$name" "$kind" | normalize)"
    title="$(jq -r .name <<<"$want")"
    id="$(jq -r --arg n "$title" '.[] | select(.name == $n) | .id' <<<"$live")"
    if [ -z "$id" ]; then
      echo "$name: no $title ruleset"
      differs=$((differs + 1))
      continue
    fi
    got="$(gh api "repos/$slug/rulesets/$id" | normalize)" || {
      echo "$name: cannot read its $title ruleset"
      differs=$((differs + 1))
      continue
    }
    if ! jq -e 'has("bypass_actors")' <<<"$got" >/dev/null; then
      echo "$name $kind: bypass_actors hidden from this token; compared without them"
      want="$(jq -S 'del(.bypass_actors)' <<<"$want")"
    fi
    if ! diff -u --label "$name $kind (live)" --label "$name $kind (shared)" <(echo "$got") <(echo "$want"); then
      differs=$((differs + 1))
    fi
  done
  # a 403 is GitHub hiding a setting from a token without Administration read
  if out="$(gh api "repos/$slug/actions/permissions" --jq .sha_pinning_required 2>&1)"; then
    if [ "$out" != true ]; then
      echo "$name: actions are not required to be pinned to a full-length commit SHA"
      differs=$((differs + 1))
    fi
  elif [[ $out == *"HTTP 403"* ]]; then
    echo "$name: Actions settings hidden from this token; SHA pinning not compared"
  else
    echo "$name: cannot read its Actions settings"
    differs=$((differs + 1))
  fi
  # and a 404 its answer for a repository without immutable releases
  want="$(ci_immutable_releases "$name")"
  if out="$(gh api "repos/$slug/immutable-releases" --jq .enabled 2>&1)"; then
    got=$out
  elif [[ $out == *"HTTP 404"* ]]; then
    got=false
  elif [[ $out == *"HTTP 403"* ]]; then
    echo "$name: immutable releases hidden from this token; not compared"
    got=$want
  else
    echo "$name: cannot read whether its releases are immutable"
    return $((differs + 1))
  fi
  if [ "$got" != "$want" ]; then
    echo "$name: immutable releases enabled is $got, but immutable_releases is $want"
    differs=$((differs + 1))
  fi
  return "$differs"
}

case ${1:-} in
render)
  [ $# = 3 ] || {
    echo "usage: $0 render NAME main|dev|stable" >&2
    exit 2
  }
  render "$2" "$3"
  ;;
diff)
  shift
  repos="$(ci_covered "$@")"
  failed=0
  while read -r slug branch; do
    kinds=(main dev stable)
    # this repository: its main alone
    [ "$branch" != - ] || kinds=(main)
    # set -e turned back on inside a subshell outside any `if` or `||` (it
    # inherits the +e), so a failure stops this repository alone
    set +e
    (
      set -e
      GH_TOKEN="$(ci_token "${slug#*/}")"
      export GH_TOKEN
      diff_repo "$slug" "${kinds[@]}"
    )
    rc=$?
    set -e
    failed=$((failed + rc))
  done <<<"$repos"
  exit "$failed"
  ;;
*)
  echo "usage: $0 render NAME main|dev|stable | diff [NAME...]" >&2
  exit 2
  ;;
esac
