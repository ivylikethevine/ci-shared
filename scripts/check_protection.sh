#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fails unless each repos/<name>.toml repository has a `main` and a `dev` that
# its sync token cannot change except through a pull request: both block force
# pushes and deletion, `main` requires a pull request, and `dev` requires a
# pull request or signed commits (the token's commits are unsigned, so it
# reaches `dev` only through a pull request GitHub merges). A rule counts only
# from an active ruleset the token's own user cannot bypass outside a pull
# request; the token acts as that user. rulesets/ holds the shared rulesets
# that pass.
#
#   SYNC_TOKEN_<NAME>=<token>... scripts/check_protection.sh [NAME...]
#   GH_TOKEN=<token> scripts/check_protection.sh [NAME...]
#
# Each target is read with its own SYNC_TOKEN_<NAME>, else with GH_TOKEN; NAME
# limits the check to those targets. Fails closed: a missing token, an invalid
# repos/ config, an API error, a response of the wrong shape or a bypass level
# it does not know each fail the branch. Prints one line per branch and exits 1
# if any fails. Each token needs Metadata read on its target, and must be the
# one the sync writes with: the bypass is read for its user.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

# check_branch <slug> <main|dev> - prints why the branch fails and fails;
# every command is checked, since a caller's `if` turns off `set -e` in here
check_branch() {
  local slug=$1 branch=$2 want='' refs rules ids id ruleset held='[]' bypassed='' missing
  # the rules each branch needs, each a rule or a list of rules any one of
  # which will do
  case $branch in
  main) want='["non_fast_forward","deletion","pull_request"]' ;;
  dev) want='["non_fast_forward","deletion",["pull_request","required_signatures"]]' ;;
  esac
  refs="$(gh api "repos/$slug/git/matching-refs/heads/$branch")" || {
    echo "cannot list its refs"
    return 1
  }
  # matching-refs matches by prefix, so the exact ref is picked out
  jq -e --arg r "refs/heads/$branch" 'type == "array" and any(.[]; .ref == $r)' <<<"$refs" >/dev/null || {
    echo "no such branch"
    return 1
  }
  rules="$(gh api "repos/$slug/rules/branches/$branch?per_page=100")" || {
    echo "cannot read its rules"
    return 1
  }
  ids="$(jq -er 'if type == "array" then [.[].ruleset_id | numbers] | unique | map(tostring) | join(" ")
    else error("not a list") end' <<<"$rules")" || {
    echo "unexpected rules response"
    return 1
  }
  for id in $ids; do
    ruleset="$(gh api "repos/$slug/rulesets/$id")" || {
      echo "cannot read ruleset $id"
      return 1
    }
    # a bypass level missing from the response, or one GitHub adds later, does
    # not count
    if jq -e --argjson id "$id" '.id == $id and .enforcement == "active"
      and (.current_user_can_bypass | IN("never", "pull_requests_only"))' <<<"$ruleset" >/dev/null; then
      held="$(jq -ec --argjson id "$id" --argjson h "$held" '$h + [.[] | select(.ruleset_id == $id) | .type]' <<<"$rules")" || {
        echo "cannot read ruleset $id's rules"
        return 1
      }
    else
      bypassed="$bypassed $(jq -r '"\(.name) (\(.enforcement), bypass \(.current_user_can_bypass))"' <<<"$ruleset" || echo "$id")"
    fi
  done
  missing="$(jq -enr --argjson r "$want" --argjson h "$held" '
    [$r[] | select(if type == "array" then any(.[]; IN($h[])) | not else IN($h[]) | not end)
      | if type == "array" then join(" or ") else . end] | join(", ")')" || {
    echo "cannot compare its rules"
    return 1
  }
  if [ -n "$missing" ]; then
    echo "lacks $missing${bypassed:+; not counted:$bypassed}"
    return 1
  fi
}

repos="$(ci_repos "$@")"
if [ -z "$repos" ]; then
  echo "::error title=protection::repos/ lists no targets"
  exit 1
fi

failed=0
while read -r slug base extra; do
  # the sync writes only to rows this check covers: config.py's SLUG and
  # BRANCHES again, checked here too so a misread config fails closed
  if [[ ! $slug =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || [ -n "$extra" ] ||
    { [ "$base" != main ] && [ "$base" != dev ]; }; then
    echo "::error title=protection::target '$slug $base${extra:+ $extra}' is not 'owner/name main|dev'"
    failed=1
    continue
  fi
  if ! token="$(ci_token "${slug#*/}" 2>&1)"; then
    echo "::error title=protection $slug::$token"
    failed=1
    continue
  fi
  export GH_TOKEN="$token"
  for branch in main dev; do
    if out="$(check_branch "$slug" "$branch" 2>&1)"; then
      echo "$slug $branch: protected"
    else
      echo "::error title=protection $slug $branch::${out//$'\n'/ }"
      failed=1
    fi
  done
done <<<"$repos"

exit "$failed"
