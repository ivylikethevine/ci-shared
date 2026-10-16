#!/usr/bin/env bash
# Copies files/ into the local checkouts, each receiving the paths its
# repos/<name>.toml lists, templates rendered with the values it gives them.
#
#   scripts/sync_local.sh [--check] [ROOT]
#
# ROOT holds one checkout per repos/<name>.toml, named after the repository
# (default: this checkout's parent directory); a missing checkout is skipped.
# A path with uncommitted changes in the checkout is left alone and reported.
# --check writes nothing and reports each copy that differs. Exits with the
# number of paths reported.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load

check=0
if [ "${1:-}" = --check ]; then
  check=1
  shift
fi
root="${1:-$(dirname "$CI_SHARED_DIR")}"

problems=0
while read -r slug _; do
  name="${slug#*/}"
  dir="$root/$name"
  if [ ! -d "$dir/.git" ]; then
    echo "$name: no checkout at $dir, skipped"
    continue
  fi
  changed=0
  # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
  while read -r path vars; do
    src="$CI_SHARED_DIR/files/$path"
    dst="$dir/$path"
    if [ -f "$dst" ] && ci_render "$path" $vars | cmp -s - "$dst" &&
      [ "$(ci_mode "$src")" = "$(ci_mode "$dst")" ]; then
      continue
    fi
    if [ "$check" = 1 ]; then
      echo "$name: $path differs"
      problems=$((problems + 1))
      continue
    fi
    if [ -f "$dst" ] && ! git -C "$dir" diff --quiet HEAD -- "$path"; then
      echo "$name: $path has uncommitted changes, left alone" >&2
      problems=$((problems + 1))
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    ci_render "$path" $vars >"$dst"
    if [ -x "$src" ]; then chmod +x "$dst"; else chmod -x "$dst"; fi
    echo "$name: $path updated"
    changed=$((changed + 1))
  done < <(ci_targets "$name")
  [ "$check" = 1 ] || echo "$name: $changed file(s) updated"
done < <(ci_repos)

exit $((problems > 255 ? 255 : problems))
