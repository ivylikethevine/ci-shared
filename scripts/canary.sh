#!/usr/bin/env bash
# Runs each target's canary, the command its repos/<name>.toml gives as
# `canary`, in a clone of its sync branch with files/ written in as the sync
# would write them: a target's test that reads a shared file fails here, on the
# change to files/, before it fails that target's sync pull request. The
# checks workflow runs it on every push and pull request.
#
#   scripts/canary.sh [NAME...]
#
# NAME limits the run to those targets; a target with no canary is skipped.
# Each clone comes from $CI_CANARY_REMOTE/<owner>/<name>.git (default
# https://github.com), shallow, with no credentials. The command runs from the
# clone's root with no shell between, its output in a group under GitHub
# Actions. Exits with the number of targets that failed.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load
ci_tmpdir

remote="${CI_CANARY_REMOTE:-https://github.com}"
targets="$(ci_repos "$@")"
root="$CI_TMP/root"
mkdir -p "$root"

# the targets with a canary, each cloned at its sync branch
canaries=()
declare -A branches=()
failed=0
while read -r slug branch; do
  name="${slug#*/}"
  if [ "$(ci_entry "$name" | jq '.canary | length')" = 0 ]; then
    echo "$name: no canary, skipped"
    continue
  fi
  if ! git clone -q --depth 1 --branch "$branch" -- "$remote/$slug.git" "$root/$name"; then
    echo "::error title=canary $name::could not clone $slug at $branch"
    failed=$((failed + 1))
    continue
  fi
  canaries+=("$name")
  branches[$name]=$branch
done <<<"$targets"

if [ ${#canaries[@]} -gt 0 ]; then
  # every clone at once; a target with none beside it is reported and skipped
  "$CI_SCRIPTS_DIR/sync_local.sh" "$root" | { grep -v ': no checkout at ' || true; }
fi

for name in ${canaries[@]+"${canaries[@]}"}; do
  mapfile -t cmd < <(ci_entry "$name" | jq -r '.canary[]')
  [ -z "${GITHUB_ACTIONS:-}" ] || echo "::group::canary $name: ${cmd[*]}"
  rc=0
  (cd "$root/$name" && "${cmd[@]}") || rc=$?
  [ -z "${GITHUB_ACTIONS:-}" ] || echo "::endgroup::"
  if [ "$rc" = 0 ]; then
    echo "$name: canary passed"
  else
    echo "::error title=canary $name::${cmd[*]} exited $rc on $name's ${branches[$name]} with files/ written in"
    failed=$((failed + 1))
  fi
done

exit $((failed > 255 ? 255 : failed))
