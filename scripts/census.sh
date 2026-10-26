#!/usr/bin/env bash
# Groups the CI and tooling files that two or more local checkouts track by
# content, to find what can move into files/ and which copies have drifted.
#
#   scripts/census.sh [--drift | --gaps] [ROOT]
#
# ROOT holds one checkout per repos/<name>.toml, named after the repository
# (default: this checkout's parent directory). The census covers every path in
# files/ and every tracked path CI_CENSUS_PATTERN matches: workflows, actions,
# lint and editor configs, the docs site's config. Each path prints once, then
# one line per distinct copy: blob, mode, the repositories holding it, and
# "= files/" when it matches the copy here, rendered with the repository's
# template values. --drift prints only paths with more than one copy. --gaps
# prints, for each path in files/, the targets that hold a copy their
# repos/<name>.toml does not list (a copy the sync never refreshes) and the
# targets that hold none at all.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load
rows="$(ci_rows)"

mode=all
case "${1:-}" in
--drift | --gaps)
  mode="${1#--}"
  shift
  ;;
esac
root="${1:-$(dirname "$CI_SHARED_DIR")}"

CI_CENSUS_PATTERN='^(\.github/|\.vscode/|\.zed/|\.claude/settings\.json$|\.editorconfig$|\.gitattributes$|\.gitignore$|\.dockerignore$|\.prettierignore$|\.markdownlint|\.prettier|\.shellcheckrc$|\.typos\.toml$|\.hadolint\.yaml$|\.moxide\.toml$|\.scorecard\.yml$|\.gitleaks\.toml$|\.tool-versions$|_config\.yml$|lychee\.toml$|LICENSE\.md$|docs/CODE_OF_CONDUCT\.md$)'

# the paths files/ holds, one per line, and as a set
shared="$(ci_shared_paths)"
declare -A is_shared=()
while read -r path; do [ -z "$path" ] || is_shared[$path]=1; done <<<"$shared"

# each target's template values, by "name path"; a key per path it lists
declare -A values=()
while read -r name path vars; do
  values["$name $path"]="$vars"
done <<<"$rows"

# gaps - each path in files/ against each target: listed in its toml, held in
# its checkout, both or neither
gaps() {
  local slug name path
  local -A held
  while read -r slug _; do
    name="${slug#*/}"
    [ -d "$root/$name/.git" ] || continue
    held=()
    while read -r path; do held[$path]=1; done < <(git -C "$root/$name" ls-files)
    while read -r path; do
      [ -n "$path" ] || continue
      [ -z "${values["$name $path"]+x}" ] || continue
      if [ -n "${held[$path]:-}" ] && [ -f "$root/$name/$path" ]; then
        printf '%s\tunlisted\t%s\n' "$path" "$name"
      else
        printf '%s\tmissing\t%s\n' "$path" "$name"
      fi
    done <<<"$shared"
  done < <(ci_repos) |
    sort |
    awk -F'\t' '
      $1 != path { if (path != "") flush(); path = $1; split("", names) }
      { names[$2] = names[$2] (names[$2] == "" ? "" : " ") $3 }
      END { if (path != "") flush() }
      function flush() {
        print path
        if ("unlisted" in names) print "  unlisted  " names["unlisted"]
        if ("missing" in names) print "  missing   " names["missing"]
      }
    '
}

if [ "$mode" = gaps ]; then
  gaps
  exit
fi

while read -r slug _; do
  name="${slug#*/}"
  [ -d "$root/$name/.git" ] || continue
  # the working tree's copies, uncommitted edits included, not the index's
  git -C "$root/$name" ls-files |
    while read -r path; do
      [ -f "$root/$name/$path" ] || continue
      [[ $path =~ $CI_CENSUS_PATTERN ]] || [ -n "${is_shared[$path]:-}" ] || continue
      blob="$(git hash-object "$root/$name/$path")"
      echo "$path ${blob:0:7} $(ci_mode "$root/$name/$path") $name"
    done
done < <(ci_repos) |
  sort |
  while read -r path blob mode_bits repo; do
    here=""
    if [ -f "$CI_SHARED_DIR/files/$path" ]; then
      vars="${values["$repo $path"]:-}"
      # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
      if [ "$(ci_render "$path" $vars | git hash-object --stdin | cut -c1-7)" = "$blob" ]; then
        here=" = files/"
      fi
    fi
    printf '%s\t%s %s%s\t%s\n' "$path" "$blob" "$mode_bits" "$here" "$repo"
  done |
  awk -F'\t' -v drift="$([ "$mode" = drift ] && echo 1 || echo 0)" '
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
