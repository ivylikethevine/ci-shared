#!/usr/bin/env bash
# Writes USAGE.md: each file in files/, the repositories whose targets list
# it, and how many there are, with a total per repository; then each
# template's values per repository.
#
#   scripts/usage.sh [--check]
#
# --check writes nothing and fails when USAGE.md is out of date.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="$CI_SHARED_DIR/USAGE.md"

render() {
  local names=() slug
  while read -r slug _; do names+=("${slug#*/}"); done < <(ci_repos)

  printf '# Usage\n\n'
  printf 'Which repositories receive each shared file, written by\n'
  # shellcheck disable=SC2016 # the backticks are Markdown
  printf '`scripts/usage.sh` from `targets/`; run it after changing a target list.\n\n'

  (
    cd "$CI_SHARED_DIR/files"
    find . -type f | sed 's|^\./||' | LC_ALL=C sort
  ) | while read -r path; do
    row="\`$path\`"
    count=0
    for name in "${names[@]}"; do
      if ci_target_row "$name" "$path" >/dev/null; then
        row="$row"$'\t'x
        count=$((count + 1))
      else
        row="$row"$'\t'
      fi
    done
    printf '%s\t%s\n' "$row" "$count"
  done | awk -F'\t' -v header="File	${names[*]}	Repos" '
    BEGIN { gsub(/ /, "\t", header); n = split(header, h, "\t") }
    {
      rows[NR] = $0
      for (i = 2; i < n; i++) if ($i == "x") total[i]++
    }
    END {
      nr = NR
      line = "**Files per repository**"
      for (i = 2; i < n; i++) line = line "\t" total[i] + 0
      rows[++nr] = line "\t" NR
      for (i = 1; i <= n; i++) w[i] = length(h[i])
      for (r = 1; r <= nr; r++) {
        split(rows[r], f, "\t")
        for (i = 1; i <= n; i++) if (length(f[i]) > w[i]) w[i] = length(f[i])
      }
      emit(h)
      for (i = 1; i <= n; i++) sep[i] = dashes(w[i])
      emit(sep)
      for (r = 1; r <= nr; r++) { split(rows[r], f, "\t"); emit(f) }
    }
    function dashes(k,   s) { s = ""; while (k-- > 0) s = s "-"; return s }
    function emit(a,   i, s) {
      s = "|"
      for (i = 1; i <= n; i++) s = s sprintf(" %-*s |", w[i], a[i])
      print s
    }
  '
}

# The values each repository gives each template, one bullet per row that
# sets any.
render_values() {
  local slug name path vars rows=""
  while read -r slug _; do
    name="${slug#*/}"
    while read -r path vars; do
      [ -n "$vars" ] || continue
      rows="$rows- \`$path\` in $name: \`$vars\`"$'\n'
    done < <(ci_targets "$name")
  done < <(ci_repos)
  [ -n "$rows" ] || return 0
  printf '\n## Template values\n\n'
  printf '%s' "$rows"
}

if [ "${1:-}" = --check ]; then
  if ! { render && render_values; } | cmp -s - "$out"; then
    echo "USAGE.md is out of date: run scripts/usage.sh" >&2
    exit 1
  fi
else
  { render && render_values; } >"$out"
fi
