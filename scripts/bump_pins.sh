#!/usr/bin/env bash
# Moves the `uses:` pins in a target's own workflows and actions (the files the
# sync does not deliver): each to the pin files/ uses for its action, or, given
# PINs, to those, for actions files/ does not pin. Prints a line per file and
# action it changed, as TSV: target, path, action. Nothing is committed.
#
#   scripts/bump_pins.sh NAME [PIN...]   # PIN: 'owner/action@<40 hex> # <version>'
#
# NAME's checkout is the one beside this repository, named after it.
# scripts/stale_pins.sh lists what the files/ pins would move.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if (($# == 0)); then
  echo "usage: scripts/bump_pins.sh NAME [PIN...]" >&2
  exit 2
fi
name=$1
shift
for pin; do
  [[ $pin =~ ^[A-Za-z0-9._/-]+@[0-9a-f]{40}\ \#\ [^\ ]+$ ]] || {
    echo "bump_pins: '$pin' is not 'owner/action@<40 hex> # <version>'" >&2
    exit 2
  }
done
ci_load
rows="$(ci_rows "$name")"
if (($# == 0)); then
  pins="$(ci_action_pins | sed 's/^[^ ]* //')"
else
  pins="$(printf '%s\n' "$@")"
fi
dir="$(dirname "$CI_SHARED_DIR")/$name"
[ -d "$dir" ] || {
  echo "bump_pins: no checkout of $name at $dir" >&2
  exit 2
}
ci_tmpdir
while IFS= read -r file; do
  while IFS= read -r pin; do
    action="${pin%%@*}"
    # written back through cat rather than sed -i, which BSD and GNU spell apart
    sed -E "s|(uses: )${action//./\\.}@[0-9a-f]{40} # [^ ]+|\\1${pin}|" "$dir/$file" >"$CI_TMP/new"
    cmp -s "$CI_TMP/new" "$dir/$file" && continue
    cat "$CI_TMP/new" >"$dir/$file"
    printf '%s\t%s\t%s\n' "$name" "$file" "$action"
  done <<<"$pins"
done < <(ci_own_pinned "$name" "$rows" "$dir")
