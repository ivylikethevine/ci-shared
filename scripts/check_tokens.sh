#!/usr/bin/env bash
# Prints when each target's sync token expires, and fails unless every one is
# set, can read its repository, and has more than WARN_DAYS left. A token
# GitHub reports no expiry for fails too.
#
#   SYNC_TOKEN_<NAME>=<token>... scripts/check_tokens.sh [NAME...]
#
# Reads SYNC_TOKEN_<NAME> alone, never GH_TOKEN: it checks the secrets the sync
# writes with. GitHub sends a token's expiry in the
# GitHub-Authentication-Token-Expiration header of every API response. NAME
# limits the check to those targets. Exits with the number of tokens that fail.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

WARN_DAYS=14

# check_token <slug> <secret> - prints its expiry, or why it fails and fails
check_token() {
  local slug=$1 var=$2 resp status expiry end days
  if [ -z "${!var:-}" ]; then
    echo "$var is not set"
    return 1
  fi
  resp="$(GH_TOKEN="${!var}" gh api --include "repos/$slug" 2>/dev/null)" || {
    # the status line, which --include prints for an HTTP error too
    status="$(head -n 1 <<<"$resp" | tr -d '\r')"
    echo "$var cannot read $slug${status:+ ($status)}"
    return 1
  }
  # one line: kcov stops reading a script at a multi-line awk program
  expiry="$(awk 'tolower($0) ~ /^github-authentication-token-expiration:/ { sub(/^[^:]*: */, ""); sub(/\r$/, ""); print; exit }' <<<"$resp")"
  if [ -z "$expiry" ]; then
    echo "$var has no expiry date"
    return 1
  fi
  end="$(date -d "$expiry" +%s 2>/dev/null)" || {
    echo "$var has an expiry GitHub sent as '$expiry'"
    return 1
  }
  days=$(((end - $(date +%s)) / 86400))
  if [ "$days" -lt "$WARN_DAYS" ]; then
    echo "$var expires $expiry, in $days days: renew it"
    return 1
  fi
  echo "$var expires $expiry, in $days days"
}

failed=0
while read -r slug _; do
  name="${slug#*/}"
  if out="$(check_token "$slug" "$(ci_token_secret "$name")")"; then
    echo "$name: $out"
  else
    echo "::error title=token $name::$out"
    failed=$((failed + 1))
  fi
done < <(ci_repos "$@")

exit "$failed"
