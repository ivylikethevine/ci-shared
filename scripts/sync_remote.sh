#!/usr/bin/env bash
# Opens or updates one pull request per repos/<name>.toml that brings the
# paths it lists in line with files/, templates rendered with the values it
# gives them.
#
#   GH_TOKEN=<token> scripts/sync_remote.sh [--dry-run] [NAME...]
#
# Works through the Git data API, so nothing is cloned: one commit on the base
# branch's head, on branch `ci-sync` (force-moved each run), and one pull
# request from it, updated in place while open. A repository already in line
# gets nothing. NAME limits the run to those repositories; --dry-run reports
# what differs and writes nothing. A run that writes first runs
# check_protection.sh and stops if it fails. The token needs Contents, Pull
# requests and Workflows read/write on each target. Exits with the number of
# repositories that failed.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

BRANCH=ci-sync
TITLE='ci: sync shared CI files'

dry=0
if [ "${1:-}" = --dry-run ]; then
  dry=1
  shift
fi
source_sha="${SOURCE_SHA:-$(git -C "$CI_SHARED_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"

# every target, whatever NAME limits the run to: the token reaches all
if [ "$dry" = 0 ] && ! "$CI_SCRIPTS_DIR/check_protection.sh"; then
  echo "::error title=sync::a target's branch protection failed the check; nothing was written"
  exit 1
fi

# Uploads one file as a blob and checks GitHub stored the bytes git hashes.
upload_blob() {
  local slug=$1 src=$2 sha
  sha="$(base64 <"$src" | tr -d '\n' | jq -Rs '{encoding: "base64", content: .}' |
    gh api "repos/$slug/git/blobs" --input - --jq .sha)"
  [ "$sha" = "$(git hash-object "$src")" ] || {
    echo "blob for $src came back as $sha" >&2
    return 1
  }
}

sync_repo() {
  local slug=$1 base=$2 name=${1#*/}
  local head tree listing path vars src rendered mode want have entries='' files=''
  head="$(gh api "repos/$slug/git/ref/heads/$base" --jq .object.sha)"
  tree="$(gh api "repos/$slug/git/commits/$head" --jq .tree.sha)"
  listing="$(gh api "repos/$slug/git/trees/$tree?recursive=1")"
  if [ "$(jq -r .truncated <<<"$listing")" = true ]; then
    echo "$name: the tree listing of $base is truncated" >&2
    return 1
  fi

  rendered="$(mktemp "${TMPDIR:-/tmp}/ci-sync.XXXXXX")"
  # sync_repo runs in its own subshell, so this fires as each repository ends
  # shellcheck disable=SC2064 # expanded now: the local is gone by exit time
  trap "rm -f '$rendered'" EXIT
  # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
  while read -r path vars; do
    src="$CI_SHARED_DIR/files/$path"
    ci_render "$path" $vars >"$rendered"
    mode="$(ci_mode "$src")"
    want="$(git hash-object "$rendered") $mode"
    have="$(jq -r --arg p "$path" '.tree[] | select(.path == $p) | "\(.sha) \(.mode)"' <<<"$listing")"
    [ "$want" != "$have" ] || continue
    echo "$name: $path differs"
    files="$files- \`$path\`"$'\n'
    entries="$entries$path"$'\t'"$mode"$'\t'"${want%% *}"$'\n'
    [ "$dry" = 1 ] || upload_blob "$slug" "$rendered"
  done < <(ci_targets "$name")

  if [ -z "$files" ]; then
    echo "$name: in line with files/"
    return 0
  fi
  [ "$dry" = 0 ] || return 0

  local new_tree commit pr body
  # one `path<TAB>mode<TAB>sha` line per entry
  new_tree="$(printf '%s' "$entries" | jq -Rn --arg b "$tree" \
    '{base_tree: $b, tree: [inputs | split("\t") | {path: .[0], mode: .[1], type: "blob", sha: .[2]}]}' |
    gh api "repos/$slug/git/trees" --input - --jq .sha)"
  commit="$(jq -n --arg m "$TITLE"$'\n\n'"Source: $source_sha" --arg t "$new_tree" --arg p "$head" \
    '{message: $m, tree: $t, parents: [$p]}' |
    gh api "repos/$slug/git/commits" --input - --jq .sha)"
  if gh api "repos/$slug/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
    gh api -X PATCH "repos/$slug/git/refs/heads/$BRANCH" -f sha="$commit" -F force=true >/dev/null
  else
    gh api "repos/$slug/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$commit" >/dev/null
  fi

  body="Brings the shared CI files in line with source commit \`$source_sha\`. Change the source copy, not this branch: the next sync overwrites it."$'\n\n'"$files"
  pr="$(gh api "repos/$slug/pulls?head=${slug%%/*}:$BRANCH&base=$base&state=open" --jq '.[0].number // empty')"
  if [ -n "$pr" ]; then
    gh api -X PATCH "repos/$slug/pulls/$pr" -f body="$body" >/dev/null
    echo "$name: updated pull request #$pr"
  else
    pr="$(gh api "repos/$slug/pulls" -f title="$TITLE" -f head="$BRANCH" -f base="$base" -f body="$body" --jq .number)"
    echo "$name: opened pull request #$pr"
  fi
}

failed=0
while read -r slug base; do
  name="${slug#*/}"
  # set -e turned back on inside a subshell outside any `if` or `||` (it
  # inherits the +e), so a failure stops this repository alone
  set +e
  (
    set -e
    sync_repo "$slug" "$base"
  )
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "::error title=sync $name::sync failed, see the lines above"
    failed=$((failed + 1))
  fi
done < <(ci_repos "$@")

exit "$failed"
