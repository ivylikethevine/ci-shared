# shellcheck shell=bash
# Helpers shared by the scripts in this directory; sourced, not run.

CI_SHARED_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# ci_load - reads every repos/<name>.toml into CI_CONFIGS as one JSON list
# (scripts/config.py), or fails when any of them is invalid. Each script runs it
# once before the helpers below, which read CI_CONFIGS.
ci_load() {
  CI_CONFIGS="$(python3 -I "$CI_SHARED_DIR/scripts/config.py")"
}

ci_configs() {
  if [ -z "${CI_CONFIGS:-}" ]; then
    echo "ci_load has not run" >&2
    return 1
  fi
  printf '%s\n' "$CI_CONFIGS"
}

# Prints "owner/name branch" for each target, branch being where its sync pull
# requests go.
ci_repos() {
  ci_configs | jq -r '.[] | "\(.repository) \(.sync_branch)"'
}

# Prints a row per path target <name> receives: the path in files/, then any
# key=value pairs its template takes. Fails when there is no target <name>.
ci_targets() {
  ci_configs | jq -r --arg n "$1" '
    first(.[] | select(.name == $n)) // error("no target \($n)")
    | .templates as $t
    | .files[]
    | [., (($t[.] // {}) | to_entries[] | "\(.key)=\(.value)")]
    | join(" ")'
}

# ci_ruleset_values <name> - prints the JSON values target <name> gives the
# shared main ruleset.
ci_ruleset_values() {
  ci_configs | jq -ec --arg n "$1" 'first(.[] | select(.name == $n)).rulesets.main'
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
