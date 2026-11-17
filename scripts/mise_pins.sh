#!/usr/bin/env bash
# Checks the shared mise file against tools.txt, both as each target that
# receives the mise file renders them: every tools.txt row is a [tools] entry
# at its pin, keyed by the tool's name or a backend path ending in it
# (`"aqua:owner/name"`), or is named on the file's `apt:` comment line; every
# entry and every apt name is a row. scripts/check.sh runs it.
#
#   scripts/mise_pins.sh
#
# Prints one line per difference and exits with their number.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load
ci_tmpdir

MISE=.config/mise/conf.d/ci-tools.toml
TOOLS=.github/actions/setup-tool/tools.txt

# tools.txt's rows (name|pin|...), then the mise file: one line per difference,
# each starting with target <t>'s name
# shellcheck disable=SC2016 # awk's $vars, not the shell's
compare='
  FNR == NR {
    if ($0 !~ /^#/ && $0 != "") { split($0, f, "|"); pin[f[1]] = f[2] }
    next
  }
  /^#.*apt:/ {
    sub(/^#.*apt:[[:space:]]*/, "")
    n = split($0, a, /[[:space:]]+/)
    for (i = 1; i <= n; i++) if (a[i] != "") apt[a[i]] = 1
    next
  }
  /^\[/ { in_tools = ($0 == "[tools]"); next }
  !in_tools || /^[[:space:]]*(#|$)/ { next }
  {
    key = $0; sub(/[[:space:]]*=.*/, "", key); gsub(/"/, "", key)
    val = $0; sub(/^[^=]*=[[:space:]]*"/, "", val); sub(/".*/, "", val)
    tool = key; sub(/.*[\/:]/, "", tool)
    if (!(tool in pin)) { print t ": " key " is no tools.txt row"; next }
    seen[tool] = 1
    if (val != pin[tool]) print t ": " key " " val " is not the tools.txt pin " pin[tool]
  }
  END {
    for (k in pin) if (!(k in seen) && !(k in apt))
      print t ": tools.txt pins " k " " pin[k] ", which the mise file neither lists nor names under apt:"
    for (k in apt) if (!(k in pin)) print t ": apt: names " k ", no tools.txt row"
  }
'

rows="$(ci_rows)"
found=0
# shellcheck disable=SC2086 # $vars is key=value words, split on purpose
while read -r name path vars; do
  [ "$path" = "$MISE" ] || continue
  tools="$(awk -v n="$name" -v p="$TOOLS" '$1 == n && $2 == p { $1 = $2 = ""; print "x" $0 }' <<<"$rows")"
  if [ -z "$tools" ]; then
    echo "$name: receives $MISE but not $TOOLS"
    found=$((found + 1))
    continue
  fi
  tools="${tools#x}"
  ci_render "$TOOLS" $tools >"$CI_TMP/tools"
  ci_render "$MISE" $vars >"$CI_TMP/mise"
  diffs="$(awk -v t="$name" "$compare" "$CI_TMP/tools" "$CI_TMP/mise" | LC_ALL=C sort)"
  [ -n "$diffs" ] || continue
  printf '%s\n' "$diffs"
  found=$((found + $(wc -l <<<"$diffs")))
done <<<"$rows"

exit $((found > 255 ? 255 : found))
