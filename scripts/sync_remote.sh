#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Opens or updates one pull request per repos/<name>.toml that brings the
# paths it lists in line with files/, templates rendered with the values it
# gives them.
#
#   SYNC_TOKEN_<NAME>=<token>... SYNC_SIGNING_KEY=<private key> \
#   SYNC_COMMITTER_NAME=<name> SYNC_COMMITTER_EMAIL=<email> \
#     scripts/sync_remote.sh [--dry-run] [NAME...]
#
# Works through the Git data API, so nothing is cloned: one commit on the base
# branch's head, on branch `ci-sync` (force-moved each run), and one pull
# request from it, updated in place while open. A repository already in line
# gets nothing. NAME limits the run to those repositories; --dry-run reports
# what differs and writes nothing. Each target is written with its own token,
# SYNC_TOKEN_<NAME> (else GH_TOKEN, for a local run), which needs Contents,
# Pull requests and Workflows read/write on that target alone. Before writing
# to a target, check_protection.sh runs on it, and a target that fails gets
# nothing. Exits with the number of repositories that failed. When
# GITHUB_STEP_SUMMARY is set (an Actions job), a Markdown section per target
# saying what it got, file by file, is appended to it.
#
# The targets require signed commits, so each commit is signed here with
# SYNC_SIGNING_KEY, an unencrypted OpenSSH private key registered as a signing
# key on the GitHub account whose verified email is SYNC_COMMITTER_EMAIL. A
# commit GitHub stores with other bytes than were signed, or does not verify,
# fails its target before the branch moves.
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

# summary <line>... - appends the lines to the job summary, when there is one
summary() {
  printf '%s\n' "$@" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}
source_ref="\`$source_sha\`"
# a link where the workflow runs, a bare sha in a local run
[ -z "${GITHUB_REPOSITORY:-}" ] || source_ref="[$source_ref](${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/commit/$source_sha)"
summary "## Sync$([ "$dry" = 0 ] || echo ' (dry run)')" '' "Source commit $source_ref." ''

keyfile=''
if [ "$dry" = 0 ]; then
  for var in SYNC_SIGNING_KEY SYNC_COMMITTER_NAME SYNC_COMMITTER_EMAIL; do
    if [ -z "${!var:-}" ]; then
      echo "$var is not set; the sync commits are signed" >&2
      exit 1
    fi
  done
  keyfile="$(mktemp "${TMPDIR:-/tmp}/ci-sync-key.XXXXXX")"
  trap 'rm -f "$keyfile"' EXIT
  printf '%s\n' "$SYNC_SIGNING_KEY" >"$keyfile"
  # the key reaches ssh-keygen through the file alone, never gh's environment
  unset SYNC_SIGNING_KEY
  if ! ssh-keygen -y -P '' -f "$keyfile" >/dev/null 2>&1; then
    echo "SYNC_SIGNING_KEY is not an unencrypted OpenSSH private key" >&2
    exit 1
  fi
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

# create_commit <slug> <tree> <parent> <message> - creates the commit, signed
# with the sync key, and prints its sha. Fails unless GitHub stored the bytes
# that were signed and verified the signature.
create_commit() {
  local slug=$1 tree=$2 parent=$3 msg=$4 now ident headers sig want got
  now="$(date +%s)"
  ident="$SYNC_COMMITTER_NAME <$SYNC_COMMITTER_EMAIL> $now +0000"
  headers="tree $tree"$'\n'"parent $parent"$'\n'"author $ident"$'\n'"committer $ident"$'\n'
  # git signs the commit object without its gpgsig header
  sig="$(printf '%s\n%s' "$headers" "$msg" | ssh-keygen -q -Y sign -f "$keyfile" -n git)"
  # the stored object: the signature as a header, continuation lines indented
  want="$(printf '%sgpgsig %s\n\n%s' "$headers" "${sig//$'\n'/$'\n' }" "$msg" | git hash-object -t commit --stdin)"
  got="$(jq -n --arg m "$msg" --arg t "$tree" --arg p "$parent" --arg s "$sig" \
    --arg n "$SYNC_COMMITTER_NAME" --arg e "$SYNC_COMMITTER_EMAIL" --argjson d "$now" '
      {name: $n, email: $e, date: ($d | todate)} as $who
      | {message: $m, tree: $t, parents: [$p], author: $who, committer: $who, signature: $s}' |
    gh api "repos/$slug/git/commits" --input - --jq '"\(.sha) \(.verification.verified) \(.verification.reason)"')"
  if [ "${got%% *}" != "$want" ]; then
    echo "the commit came back as ${got%% *}, not the $want that was signed" >&2
    return 1
  fi
  if [ "$(cut -d' ' -f2 <<<"$got")" != true ]; then
    echo "GitHub did not verify the commit's signature: ${got##* }" >&2
    return 1
  fi
  printf '%s\n' "$want"
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
    summary "### $name" '' "In line with \`files/\`." ''
    return 0
  fi
  if [ "$dry" = 1 ]; then
    summary "### $name" '' "Differs on \`$base\`; nothing written:" '' "$files"
    return 0
  fi

  local new_tree commit pr url body
  # one `path<TAB>mode<TAB>sha` line per entry
  new_tree="$(printf '%s' "$entries" | jq -Rn --arg b "$tree" \
    '{base_tree: $b, tree: [inputs | split("\t") | {path: .[0], mode: .[1], type: "blob", sha: .[2]}]}' |
    gh api "repos/$slug/git/trees" --input - --jq .sha)"
  commit="$(create_commit "$slug" "$new_tree" "$head" "$TITLE"$'\n\n'"Source: $source_sha")"
  if gh api "repos/$slug/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
    gh api -X PATCH "repos/$slug/git/refs/heads/$BRANCH" -f sha="$commit" -F force=true >/dev/null
  else
    gh api "repos/$slug/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$commit" >/dev/null
  fi

  body="Brings the shared CI files in line with source commit \`$source_sha\`. Change the source copy, not this branch: the next sync overwrites it."$'\n\n'"$files"
  # "number url" of the open pull request, if any
  pr="$(gh api "repos/$slug/pulls?head=${slug%%/*}:$BRANCH&base=$base&state=open" --jq '.[0] | select(. != null) | "\(.number) \(.html_url)"')"
  if [ -n "$pr" ]; then
    url="${pr#* }" pr="${pr%% *}"
    gh api -X PATCH "repos/$slug/pulls/$pr" -f body="$body" >/dev/null
    echo "$name: updated pull request #$pr"
    summary "### $name" '' "Pull request [#$pr]($url) into \`$base\` updated:" '' "$files"
  else
    pr="$(gh api "repos/$slug/pulls" -f title="$TITLE" -f head="$BRANCH" -f base="$base" -f body="$body" --jq '"\(.number) \(.html_url)"')"
    url="${pr#* }" pr="${pr%% *}"
    echo "$name: opened pull request #$pr"
    summary "### $name" '' "Pull request [#$pr]($url) into \`$base\` opened:" '' "$files"
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
    GH_TOKEN="$(ci_token "$name")"
    export GH_TOKEN
    # each token reaches its own target alone, so a target that fails the
    # check stops only its own writes
    if [ "$dry" = 0 ] && ! "$CI_SCRIPTS_DIR/check_protection.sh" "$name"; then
      echo "$name: branch protection failed the check; nothing was written"
      exit 1
    fi
    sync_repo "$slug" "$base"
  )
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "::error title=sync $name::sync failed, see the lines above"
    # a target writes its section last, so a failed one has none yet
    summary "### $name" '' 'Failed; nothing written. See the log.' ''
    failed=$((failed + 1))
  fi
done < <(ci_repos "$@")

exit "$failed"
