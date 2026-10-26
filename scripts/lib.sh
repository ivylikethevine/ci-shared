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

# ci_load_self - reads rulesets/self.toml, this repository's own values in the
# shared main ruleset, into CI_SELF (null without one), and its owner/name into
# CI_SELF_REPO (empty without one). The rulesets and protection checks cover
# this repository's main through it; the sync never reads it.
ci_load_self() {
  CI_SELF="$(python3 -I "$CI_SCRIPTS_DIR/config.py" --self "$CI_SHARED_DIR")"
  CI_SELF_REPO="$(jq -r '.repository // empty' <<<"$CI_SELF")"
}

# ci_tmpdir - makes CI_TMP, the one directory a script keeps its temporary
# files in, removed with them when the script exits
ci_tmpdir() {
  CI_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-tmp.XXXXXX")"
  trap 'case "$CI_TMP" in */ci-tmp.??????) rm -r "$CI_TMP" ;; esac' EXIT
}

# ci_shared_paths - prints each path files/ holds, one per line, sorted
ci_shared_paths() {
  (cd "$CI_SHARED_DIR/files" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

# the targets' entries and, once ci_load_self has run, this repository's
ci_entries() {
  ci_configs | jq -c --argjson s "${CI_SELF:-null}" '. + ([$s] - [null])'
}

# ci_covered [NAME...] - prints a row per repository the rulesets and
# protection checks cover: ci_repos' rows, then "owner/name -" for this
# repository when no NAME is given or one is its name. Fails as ci_repos does
# on a NAME that is neither.
ci_covered() {
  local self="${CI_SELF_REPO:-}" own=0 n names=()
  [ $# -gt 0 ] || own=1
  for n; do
    if [ -n "$self" ] && [ "$n" = "${self#*/}" ]; then own=1; else names+=("$n"); fi
  done
  if [ $# = 0 ] || [ ${#names[@]} -gt 0 ]; then
    ci_repos ${names[@]+"${names[@]}"} || return 1
  fi
  if [ -n "$self" ] && [ "$own" = 1 ]; then echo "$self -"; fi
}

# ci_repos [NAME...] - prints "owner/name branch" for each target, or for each
# NAME given alone, branch being where its sync pull requests go. Fails, naming
# them, when a NAME is no target, so a typo cannot pass as nothing to do; a
# script taking NAME arguments captures the output rather than reading it
# through a process substitution, whose failure it would not see.
# shellcheck disable=SC2120 # NAME is optional
ci_repos() {
  local unknown
  unknown="$(ci_configs | jq -r '($ARGS.positional - [.[].name])[]' --args "$@")"
  if [ -n "$unknown" ]; then
    echo "repos/ has no target ${unknown//$'\n'/, }" >&2
    return 1
  fi
  ci_configs | jq -r '.[] | select($ARGS.positional == [] or (.name | IN($ARGS.positional[])))
    | "\(.repository) \(.sync_branch)"' --args "$@"
}

# ci_rows [NAME...] - prints a row per path each target, or each NAME alone,
# receives: the target's name, the path in files/, then any key=value pairs
# its template takes, a space in a value spelled `%20` so the row splits on
# spaces (ci_render decodes it; scripts/config.py keeps `%` out of values). A
# template's pairs start with `repo=<name>`, set by nothing but the target's
# name. Fails as ci_repos does on a NAME that is no target.
# shellcheck disable=SC2120 # NAME is optional
ci_rows() {
  local name path vars
  local -A template=()
  ci_repos "$@" >/dev/null || return 1
  ci_configs | jq -r '.[] | select($ARGS.positional == [] or (.name | IN($ARGS.positional[])))
    | .name as $n
    | .templates as $t
    | .files[]
    | [$n, ., (($t[.] // {}) | to_entries[] | "\(.key)=\(.value | gsub(" "; "%20"))")]
    | join(" ")' --args "$@" |
    while read -r name path vars; do
      # each path read for markers once, however many targets receive it
      if [ -z "$vars" ] && [ -z "${template[$path]:-}" ]; then
        template[$path]=no
        if ci_is_template "$path"; then template[$path]=yes; fi
      fi
      if [ -n "$vars" ] || [ "${template[$path]}" = yes ]; then
        echo "$name $path repo=$name${vars:+ $vars}"
      else
        echo "$name $path"
      fi
    done
}

# ci_targets <name> - ci_rows for target <name>, without the name column
ci_targets() {
  ci_rows "$1" | cut -d' ' -f2-
}

# the branch the sync pull requests come from on every target
CI_SYNC_BRANCH=ci-sync

# ci_open_sync_pr <slug> <base> <fields> - prints the jq string <fields> of the
# sync pull request open into <base>, if any
ci_open_sync_pr() {
  gh api "repos/$1/pulls?head=${1%%/*}:$CI_SYNC_BRANCH&base=$2&state=open" --jq ".[0] | select(. != null) | $3"
}

# ci_summary <line>... - appends the lines to the job summary, when there is one
ci_summary() {
  printf '%s\n' "$@" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# ci_as_target <name> <command>... - runs the command in a subshell under
# set -e, with GH_TOKEN set to target <name>'s token, so a failure stops that
# target alone, and sets CI_RC to its exit status. It returns 0: a caller
# testing it with `if` or `||` would keep set -e off inside the command.
ci_as_target() {
  local name=$1 token
  shift
  set +e
  (
    set -e
    token="$(ci_token "$name")"
    GH_TOKEN="$token" "$@"
  )
  # shellcheck disable=SC2034 # the caller reads it
  CI_RC=$?
  set -e
}

# ci_entry <name> - prints target <name>'s entry, or this repository's, as JSON;
# fails, naming it, when there is none
ci_entry() {
  ci_entries | jq -ec --arg n "$1" 'first(.[] | select(.name == $n)) // error("no target \($n)")'
}

# ci_token_secret <name> - prints the name of the secret holding target
# <name>'s sync token, SYNC_TOKEN_<NAME>; for this repository, the variable
# its own read-only token is passed in.
ci_token_secret() {
  ci_entry "$1" | jq -r .token_secret
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

# ci_ruleset_values <name> - prints the JSON values target <name>, or this
# repository, gives the shared main ruleset.
ci_ruleset_values() {
  ci_entry "$1" | jq -ec .rulesets.main
}

# ci_immutable_releases <name> - prints true or false: whether <name>'s
# releases should be immutable.
ci_immutable_releases() {
  ci_entry "$1" | jq -r .immutable_releases
}

# ci_is_template <path> - files/<path> carries a shared: marker or `__repo__`
ci_is_template() {
  grep -qE '^[[:space:]]*(# |<!-- )shared:(if|unless|else|endif)|__repo__' "$CI_SHARED_DIR/files/$1"
}

# ci_render <path> [key=value...] - prints files/<path> as one target receives
# it. A template marks lines with `shared:if <key>` or `shared:unless <key>`
# up to `shared:endif`, kept when <key> is set or unset, or with
# `shared:if <key>=<value>[,<value>...]`, kept when <key> has one of those
# values; an optional `shared:else` keeps the lines up to `shared:endif` when
# the block's own lines go. Each marker is a `#` comment line, or `<!-- -->` in
# Markdown. It spells a value `__<key>__`; `repo` is the target's name. The
# marker lines never reach the target. A value's spaces arrive as `%20`
# (ci_targets' encoding, since the pairs travel as one line of words). A file
# with neither markers nor values is printed as it is; a `shared:else` outside
# a block, or a second one in a block, fails.
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
      hit = 0
      if (eq) {
        k = substr(cond, 1, eq - 1)
        n = split(substr(cond, eq + 1), alts, ",")
        for (i = 1; i <= n; i++) if ((k in val) && val[k] == alts[i]) hit = 1
      } else {
        hit = (cond in val)
      }
      depth++
      skip[depth] = unless ? hit : !hit
      elsed[depth] = 0
      next
    }
    /^[[:space:]]*(# |<!-- )shared:else( -->)?[[:space:]]*$/ {
      if (depth == 0 || elsed[depth]) {
        print FILENAME ":" FNR ": shared:else " (depth ? "repeated in one block" : "outside a block") >"/dev/stderr"
        exit 1
      }
      elsed[depth] = 1
      skip[depth] = !skip[depth]
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
