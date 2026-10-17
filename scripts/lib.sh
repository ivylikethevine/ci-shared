# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# Helpers shared by the scripts in this directory; sourced, not run.

CI_SCRIPTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# the tree whose repos/, files/ and rulesets/ the scripts read: this checkout,
# or the one CI_SHARED_DIR names (the tests' fixtures)
CI_SHARED_DIR="${CI_SHARED_DIR:-$(dirname "$CI_SCRIPTS_DIR")}"

# ci_load - reads every repos/<name>.toml into CI_CONFIGS as one JSON list
# (scripts/config.py), or fails when any of them is invalid. Each script runs it
# once before the helpers below, which read CI_CONFIGS.
ci_load() {
  # ci_token's fallback, kept before a script sets GH_TOKEN per target
  CI_GH_TOKEN="${GH_TOKEN:-}"
  CI_CONFIGS="$(python3 -I "$CI_SCRIPTS_DIR/config.py" "$CI_SHARED_DIR")"
}

ci_configs() {
  if [ -z "${CI_CONFIGS:-}" ]; then
    echo "ci_load has not run" >&2
    return 1
  fi
  printf '%s\n' "$CI_CONFIGS"
}

# ci_repos [NAME...] - prints "owner/name branch" for each target, or for those
# NAMEs alone, branch being where its sync pull requests go.
# shellcheck disable=SC2120 # NAMEs are optional
ci_repos() {
  ci_configs | jq -r '.[] | select($ARGS.positional == [] or (.name | IN($ARGS.positional[])))
    | "\(.repository) \(.sync_branch)"' --args "$@"
}

# Prints a row per path target <name> receives: the path in files/, then any
# key=value pairs its template takes, a space in a value spelled `%20` so the
# row splits on spaces (ci_render decodes it; scripts/config.py keeps `%` out
# of values). Fails when there is no target <name>.
ci_targets() {
  ci_configs | jq -r --arg n "$1" '
    first(.[] | select(.name == $n)) // error("no target \($n)")
    | .templates as $t
    | .files[]
    | [., (($t[.] // {}) | to_entries[] | "\(.key)=\(.value | gsub(" "; "%20"))")]
    | join(" ")'
}

# ci_token_secret <name> - prints the name of the secret holding target
# <name>'s sync token, SYNC_TOKEN_<NAME>.
ci_token_secret() {
  ci_configs | jq -er --arg n "$1" 'first(.[] | select(.name == $n)).token_secret // error("no target \($n)")'
}

# ci_token <name> - prints target <name>'s sync token: its SYNC_TOKEN_<NAME>,
# else the GH_TOKEN the script started with (a local run with one token for
# every target). Fails, naming the secret, when neither is set.
ci_token() {
  local var
  var="$(ci_token_secret "$1")" || return 1
  if [ -n "${!var:-}" ]; then
    printf '%s\n' "${!var}"
  elif [ -n "${CI_GH_TOKEN:-}" ]; then
    printf '%s\n' "$CI_GH_TOKEN"
  else
    echo "no token: $var is not set" >&2
    return 1
  fi
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

# ci_is_template <path> - files/<path> carries a shared: marker
ci_is_template() {
  grep -qE '^[[:space:]]*(# |<!-- )shared:(if|unless|endif)' "$CI_SHARED_DIR/files/$1"
}

# ci_render <path> [key=value...] - prints files/<path> as one target receives
# it. A template marks lines with `shared:if <key>` or `shared:unless <key>`
# up to `shared:endif`, kept when <key> is set or unset, or with
# `shared:if <key>=<value>`, kept when <key> has that value; each marker is a
# `#` comment line, or `<!-- -->` in Markdown. It spells a value `__<key>__`.
# The marker lines never reach the target. A value's spaces arrive as `%20`
# (ci_targets' encoding, since the pairs travel as one line of words). A file
# with neither markers nor values is printed as it is.
ci_render() {
  local path="$1" src="$CI_SHARED_DIR/files/$1"
  shift
  if [ $# -eq 0 ] && ! ci_is_template "$path"; then
    cat "$src"
    return
  fi
  awk -v vars="$*" '
    BEGIN {
      n = split(vars, kv, " ")
      for (i = 1; i <= n; i++) {
        eq = index(kv[i], "=")
        v = substr(kv[i], eq + 1)
        gsub(/%20/, " ", v)
        val[substr(kv[i], 1, eq - 1)] = v
      }
    }
    /^[[:space:]]*(# |<!-- )shared:(if|unless) [A-Za-z_]+(=[^[:space:]]+)?( -->)?[[:space:]]*$/ {
      cond = $0
      sub(/^[[:space:]]*(# |<!-- )shared:/, "", cond)
      sub(/( -->)?[[:space:]]*$/, "", cond)
      unless = (cond ~ /^unless /)
      sub(/^(if|unless) /, "", cond)
      eq = index(cond, "=")
      if (eq) {
        k = substr(cond, 1, eq - 1)
        hit = (k in val) && val[k] == substr(cond, eq + 1)
      } else {
        hit = (cond in val)
      }
      depth++
      skip[depth] = unless ? hit : !hit
      next
    }
    /^[[:space:]]*(# |<!-- )shared:endif( -->)?[[:space:]]*$/ { depth--; next }
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
