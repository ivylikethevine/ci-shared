# shellcheck shell=bash
# Helpers shared by the scripts in this directory; sourced, not run.

CI_SHARED_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Prints "owner/name branch" for each repos.txt row.
ci_repos() {
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$CI_SHARED_DIR/repos.txt"
}

# Prints each targets/<name>.txt row for repository <name>: a path from files/,
# then any key=value pairs its template takes.
ci_targets() {
  local list="$CI_SHARED_DIR/targets/$1.txt"
  [ -f "$list" ] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$list"
}

# ci_target_row <name> <path> - prints the key=value pairs <name>'s targets
# give <path>, or fails when <name> does not receive <path>.
ci_target_row() {
  ci_targets "$1" | awk -v p="$2" '
    $1 == p { f = 1; $1 = ""; sub(/^ /, ""); print }
    END { exit !f }
  '
}

# ci_render <path> [key=value...] - prints files/<path> as one target receives
# it. A template marks lines with `# shared:if <key>` or `# shared:unless <key>`
# up to `# shared:endif`, kept when <key> is set or unset, and spells a value
# `__<key>__`; the marker lines never reach the target. A file with neither
# markers nor values is printed as it is.
ci_render() {
  local src="$CI_SHARED_DIR/files/$1"
  shift
  if [ $# -eq 0 ] && ! grep -q '# shared:' "$src"; then
    cat "$src"
    return
  fi
  awk -v vars="$*" '
    BEGIN {
      n = split(vars, kv, " ")
      for (i = 1; i <= n; i++) {
        eq = index(kv[i], "=")
        val[substr(kv[i], 1, eq - 1)] = substr(kv[i], eq + 1)
      }
    }
    /^[[:space:]]*# shared:(if|unless) [A-Za-z_]+[[:space:]]*$/ {
      depth++
      skip[depth] = ($0 ~ /shared:if /) ? !($NF in val) : ($NF in val)
      next
    }
    /^[[:space:]]*# shared:endif[[:space:]]*$/ { depth--; next }
    {
      for (d = 1; d <= depth; d++) if (skip[d]) next
      line = $0
      for (k in val) gsub("__" k "__", val[k], line)
      print line
    }
  ' "$src"
}

# Prints git's mode for a file: 100755 if executable, else 100644.
ci_mode() {
  if [ -x "$1" ]; then echo 100755; else echo 100644; fi
}
