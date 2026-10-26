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
ci_load

out="$CI_SHARED_DIR/USAGE.md"
rows="$(ci_rows)"

render() {
  local names=() lists=() slug i
  # each target's paths once, as a newline-wrapped list the cells search
  while read -r slug _; do
    names+=("${slug#*/}")
    lists+=($'\n'"$(awk -v n="${slug#*/}" '$1 == n { print $2 }' <<<"$rows")"$'\n')
  done < <(ci_repos)

  printf '# Usage\n\n'
  printf 'Which repositories receive each shared file, written by\n'
  # shellcheck disable=SC2016 # the backticks are Markdown
  printf '`scripts/usage.sh` from `repos/`; run it after changing a file list there.\n\n'

  ci_shared_paths | while read -r path; do
    row="\`$path\`"
    count=0
    for i in "${!names[@]}"; do
      case "${lists[$i]}" in
      *$'\n'"$path"$'\n'*)
        row="$row"$'\t'x
        count=$((count + 1))
        ;;
      *) row="$row"$'\t' ;;
      esac
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
# sets any beyond the implicit `repo`.
render_values() {
  local name path vars lines=""
  while read -r name path vars; do
    vars="${vars#"repo=$name"}"
    vars="${vars# }"
    [ -n "$vars" ] || continue
    lines="$lines- \`$path\` in $name: \`${vars//%20/ }\`"$'\n'
  done <<<"$rows"
  [ -n "$lines" ] || return 0
  printf '\n## Template values\n\n'
  printf '%s' "$lines"
}

usage() {
  render && render_values
}

if [ "${1:-}" = --check ]; then
  if ! usage | cmp -s - "$out"; then
    echo "USAGE.md is out of date: run scripts/usage.sh" >&2
    exit 1
  fi
else
  usage >"$out"
fi
