#!/usr/bin/env bash
# Lists each `uses:` pin in a target's own workflows and actions (the files the
# sync does not deliver) that differs from the pin files/ uses for the same
# action, as TSV: target, path:line, the pin, files/'s pin. Those keep their SHA
# until a hand edit moves them; scripts/bump_pins.sh is that edit.
#
#   scripts/stale_pins.sh [NAME...]   # default: every target
#
# Reads each target's checkout beside this repository, named after it. Exits 1
# when it lists any pin, 2 when a checkout is missing.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load
if (($# == 0)); then
  mapfile -t names < <(ci_configs | jq -r '.[].name')
  set -- "${names[@]}"
fi
rows="$(ci_rows "$@")"
pins="$(ci_action_pins)"
root="$(dirname "$CI_SHARED_DIR")"
found=0 missing=0
for name; do
  dir="$root/$name"
  if [ ! -d "$dir" ]; then
    echo "stale_pins: no checkout of $name at $dir" >&2
    missing=1
    continue
  fi
  while IFS= read -r file; do
    # "<line>:<action>@<sha>" per pin in the file
    while IFS=: read -r line ref; do
      want="$(awk -v a="${ref%@*}" '$1 == a { sub(/^[^ ]+ /, ""); print }' <<<"$pins")"
      [ -n "$want" ] && [ "${want%% *}" != "$ref" ] || continue
      printf '%s\t%s:%s\t%s\t%s\n' "$name" "$file" "$line" "$ref" "$want"
      found=1
    done < <(grep -noE 'uses: [A-Za-z0-9._/-]+@[0-9a-f]{40}' "$dir/$file" | sed 's/uses: //')
  done < <(ci_own_pinned "$name" "$rows" "$dir")
done
((missing == 0)) || exit 2
exit "$found"
