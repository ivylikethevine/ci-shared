#!/usr/bin/env bash
# Opens or updates the pull request for scripts/apply_bumps.sh's changes.
#
#   GH_TOKEN=<token> GITHUB_REPOSITORY=<owner/name> scripts/bump_pr.sh <patch> <body file>
#
# Applies the patch to this checkout and writes it through the Git data API: one
# commit on HEAD, on branch `tool-bumps` (force-moved each run), and one pull
# request from it into main, opened as a draft and updated in place while open.
# The commit names no author, so GitHub signs it for the App whose token writes
# it; one GitHub does not verify fails before the branch moves. An empty patch
# writes nothing. The token needs Contents, Pull requests and Workflows write.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ $# = 2 ] || {
  echo "usage: bump_pr.sh <patch> <body file>" >&2
  exit 2
}
patch="$(realpath "$1")"
body="$(cat "$2")"
slug=$GITHUB_REPOSITORY
cd "$CI_SHARED_DIR"

BRANCH=tool-bumps
TITLE='ci: bump pinned tools'

if [ ! -s "$patch" ]; then
  echo "nothing to bump"
  exit 0
fi
git apply "$patch"

head="$(git rev-parse HEAD)"
entries=''
while IFS= read -r path; do
  [ -f "$path" ] || {
    echo "$path is no file; a bump only edits files" >&2
    exit 1
  }
  ci_upload_blob "$slug" "$path"
  entries="$entries$path"$'\t'"$(ci_mode "$path")"$'\t'"$(git hash-object "$path")"$'\n'
done < <(git diff --name-only)

tree="$(printf '%s' "$entries" | jq -Rn --arg b "$(git rev-parse 'HEAD^{tree}')" \
  '{base_tree: $b, tree: [inputs | split("\t") | {path: .[0], mode: .[1], type: "blob", sha: .[2]}]}' |
  gh api "repos/$slug/git/trees" --input - --jq .sha)"
got="$(jq -n --arg m "$TITLE" --arg t "$tree" --arg p "$head" '{message: $m, tree: $t, parents: [$p]}' |
  gh api "repos/$slug/git/commits" --input - --jq '"\(.sha) \(.verification.verified) \(.verification.reason)"')"
if [ "$(cut -d' ' -f2 <<<"$got")" != true ]; then
  echo "GitHub did not verify the commit's signature: ${got##* }" >&2
  exit 1
fi
commit="${got%% *}"

if gh api "repos/$slug/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
  gh api -X PATCH "repos/$slug/git/refs/heads/$BRANCH" -f sha="$commit" -F force=true >/dev/null
else
  gh api "repos/$slug/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$commit" >/dev/null
fi

number="$(gh api "repos/$slug/pulls?head=${slug%%/*}:$BRANCH&base=main&state=open" --jq '.[0].number // empty')"
if [ -n "$number" ]; then
  gh api -X PATCH "repos/$slug/pulls/$number" -f body="$body" >/dev/null
  echo "updated pull request #$number"
else
  number="$(gh api "repos/$slug/pulls" -f title="$TITLE" -f head="$BRANCH" -f base=main -f body="$body" -F draft=true --jq .number)"
  echo "opened pull request #$number"
fi
