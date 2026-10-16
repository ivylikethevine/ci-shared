#!/usr/bin/env bash
# Groups the CI files that two or more local checkouts track by content, to
# find what can move into files/ and which copies have drifted.
#
#   scripts/census.sh [--drift] [ROOT]
#
# ROOT holds one checkout per repos.txt row, named after the repository
# (default: this checkout's parent directory). Each path prints once, then one
# line per distinct copy: blob, mode, the repositories holding it, and
# "= files/" when it matches the copy here, rendered with the repository's
# template values. --drift prints only paths with more than one copy.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

drift=0
if [ "${1:-}" = --drift ]; then
  drift=1
  shift
fi
root="${1:-$(dirname "$CI_SHARED_DIR")}"

CI_CENSUS_PATTERN='^(\.github/|\.editorconfig$|\.markdownlint|\.prettier|\.shellcheckrc$|\.typos\.toml$|lychee\.toml$)'

while read -r slug _; do
  name="${slug#*/}"
  [ -d "$root/$name/.git" ] || continue
  # the working tree's copies, uncommitted edits included, not the index's
  git -C "$root/$name" ls-files | grep -E "$CI_CENSUS_PATTERN" |
    while read -r path; do
      [ -f "$root/$name/$path" ] || continue
      blob="$(git hash-object "$root/$name/$path")"
      echo "$path ${blob:0:7} $(ci_mode "$root/$name/$path") $name"
    done
done < <(ci_repos) |
  sort |
  while read -r path blob mode repo; do
    here=""
    if [ -f "$CI_SHARED_DIR/files/$path" ]; then
      vars="$(ci_target_row "$repo" "$path" || true)"
      # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
      if [ "$(ci_render "$path" $vars | git hash-object --stdin | cut -c1-7)" = "$blob" ]; then
        here=" = files/"
      fi
    fi
    printf '%s\t%s %s%s\t%s\n' "$path" "$blob" "$mode" "$here" "$repo"
  done |
  awk -F'\t' -v drift="$drift" '
    function flush(   k, n) {
      if (path == "" || count < 2) return
      n = 0
      for (k in groups) n++
      if (drift && n < 2) return
      print path
      for (k in groups) print "  " k "  " groups[k]
    }
    $1 != path { flush(); path = $1; count = 0; split("", groups) }
    { groups[$2] = groups[$2] (groups[$2] == "" ? "" : " ") $3; count++ }
    END { flush() }
  '
