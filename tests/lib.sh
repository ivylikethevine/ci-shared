# shellcheck shell=bash
# The harness every tests/*_test.sh sources: a fixture tree per test, fake
# commands on PATH, and assertions. A suite defines test_* functions and ends
# with `t_main`, which runs each in a subshell of its own and exits with the
# number that failed.
#
# Each test gets $T, a fresh directory holding bin/ (first on PATH), tree/
# (CI_SHARED_DIR: the repos/, files/ and rulesets/ the scripts read) and the
# checkouts a test makes beside it, so the scripts' default ROOT, tree/'s
# parent, finds them. Scripts run from this checkout's scripts/, the copies
# coverage measures.
set -euo pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(dirname "$TESTS_DIR")"
# shellcheck disable=SC2034 # read by the suites
SCRIPTS="$REPO_DIR/scripts"
_T_PATH="$PATH"

# t_setup - a fresh $T; the environment the scripts read reset to it
t_setup() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/ci-shared-test.XXXXXX")"
  mkdir -p "$T/bin" "$T/tree/repos" "$T/tree/files"
  cp -R "$REPO_DIR/rulesets" "$T/tree/"
  export T PATH="$T/bin:$_T_PATH" CI_SHARED_DIR="$T/tree" GH_LOG="$T/gh.log"
  # every SYNC_ and GITHUB_ variable too: a token of the machine's, or the
  # real job summary of a suite run in Actions, stays out of the fixtures
  # shellcheck disable=SC2046 # variable names, no spaces
  unset GH_TOKEN SOURCE_SHA CI_CONFIGS $(compgen -v | grep -E '^(SYNC|GITHUB)_' || true)
  : >"$GH_LOG"
}

t_cleanup() {
  case ${T:-} in */ci-shared-test.??????) rm -r -- "$T" ;; esac
}

# t_fail <message> - fails the running test
t_fail() {
  echo "  FAIL: $*"
  if [ -f "$T/out" ]; then sed 's/^/    | /' "$T/out"; fi
  exit 1
}

# t_run <command...> - runs it with stdout and stderr in $T/out, its exit
# status in $T_RC
t_run() {
  T_RC=0
  "$@" >"$T/out" 2>&1 || T_RC=$?
}

# t_rc <status> - the last t_run exited <status>
t_rc() {
  [ "$T_RC" = "$1" ] || t_fail "exit $T_RC, wanted $1"
}

# t_in [-x] <file> <text...> - the file holds each <text> (a fixed string;
# -x: a whole line); the file is shown on failure
t_in() {
  local opts=(-qF) f s
  if [ "$1" = -x ]; then
    opts+=(-x)
    shift
  fi
  f=$1
  shift
  for s; do
    grep "${opts[@]}" -- "$s" "$f" || t_fail "no '$s' in $f:"$'\n'"$(cat "$f")"
  done
}

# t_not_in <file> <text...> - the file holds none of them
t_not_in() {
  local f=$1 s
  shift
  for s; do
    if grep -qF -- "$s" "$f"; then t_fail "'$s' in $f"; fi
  done
}

# t_out <text...> - the last t_run printed each <text> (fixed strings)
t_out() {
  t_in "$T/out" "$@"
}

# t_no_out <text...> - the last t_run printed none of them
t_no_out() {
  t_not_in "$T/out" "$@"
}

# t_eq <got> <want> <what>
t_eq() {
  [ "$1" = "$2" ] || t_fail "$3: got '$1', wanted '$2'"
}

# t_file <path> <want> - the file holds exactly <want> and a newline
t_file() {
  [ "$(cat "$1")" = "$2" ] || t_fail "$1 holds '$(cat "$1")', wanted '$2'"
}

# t_logged <pattern> / t_not_logged <pattern> - an extended regex against the
# fake gh's call log, one "METHOD endpoint" line per call
t_logged() {
  grep -qE -- "$1" "$GH_LOG" || t_fail "no gh call matching '$1': $(tr '\n' ';' <"$GH_LOG")"
}
t_not_logged() {
  if grep -qE -- "$1" "$GH_LOG"; then t_fail "a gh call matched '$1'"; fi
}

# t_fake <name> - writes stdin to $T/bin/<name> as an executable
t_fake() {
  cat >"$T/bin/$1"
  chmod +x "$T/bin/$1"
}

# t_fake_gh - writes a fake `gh api` whose answers stdin's bash decides. The
# prologue parses the call into $method, $ep, $fields (-f/-F values), $input
# (an --input - body), $jqf (--jq) and $include (--include: 1 or 0), and logs
# "METHOD endpoint"; the body answers with `reply <json>` (filtered through
# --jq, as gh does) or `fail`.
t_fake_gh() {
  {
    cat <<'EOF'
#!/usr/bin/env bash
set -u
[ "$1" = api ] || exit 2
shift
method="" ep="" jqf="" input="" include=0 fields=()
while [ $# -gt 0 ]; do
  case $1 in
  -X) method=$2 && shift 2 ;;
  --jq) jqf=$2 && shift 2 ;;
  --input) input="$(cat)" && shift 2 ;;
  -f | -F) fields+=("$2") && shift 2 ;;
  -i | --include) include=1 && shift ;;
  *) ep=$1 && shift ;;
  esac
done
if [ -z "$method" ]; then
  method=GET
  if [ -n "$input" ] || [ ${#fields[@]} -gt 0 ]; then method=POST; fi
fi
echo "$method $ep" >>"$GH_LOG"
reply() {
  if [ -n "$jqf" ]; then jq -r "$jqf" <<<"$1"; else printf '%s\n' "$1"; fi
}
fail() {
  echo "gh: ${1:-HTTP 500}" >&2
  exit 1
}
EOF
    cat
  } | t_fake gh
}

# t_target <name> [sync_branch] [path...] - writes repos/<name>.toml for
# owner/<name> receiving those paths
t_target() {
  local name=$1 branch=${2:-dev} p
  shift $(($# < 2 ? $# : 2))
  {
    printf 'repository = "owner/%s"\nsync_branch = "%s"\nfiles = [' "$name" "$branch"
    for p; do printf '"%s", ' "$p"; done
    printf ']\n'
  } >"$T/tree/repos/$name.toml"
}

# t_toml <name> - appends stdin to repos/<name>.toml
t_toml() {
  cat >>"$T/tree/repos/$1.toml"
}

# t_shared <path> [mode] - writes stdin to tree/files/<path>
t_shared() {
  mkdir -p "$(dirname "$T/tree/files/$1")"
  cat >"$T/tree/files/$1"
  [ "${2:-}" != x ] || chmod +x "$T/tree/files/$1"
}

# t_git <dir> <args...> - git with an identity and no signing, so fixtures
# commit the same everywhere
t_git() {
  local dir=$1
  shift
  git -C "$dir" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# t_checkout <name> [path=content...] - a checkout at $T/<name> with those
# files committed
t_checkout() {
  local dir="$T/$1" kv
  shift
  mkdir -p "$dir"
  t_git "$dir" init -q
  for kv; do
    mkdir -p "$(dirname "$dir/${kv%%=*}")"
    printf '%s\n' "${kv#*=}" >"$dir/${kv%%=*}"
  done
  t_git "$dir" add -A
  t_git "$dir" commit -q --allow-empty -m fixture
}

# t_main - runs every test_* function this suite defines, or those T_ONLY (an
# extended regex) matches
t_main() {
  local fn rc pass=0 failed=0 suite
  suite="$(basename "$0" .sh)"
  for fn in $(declare -F | awk -v only="${T_ONLY:-.}" '$3 ~ /^test_/ && $3 ~ only { print $3 }'); do
    # outside any `if`, and set -e again inside: a subshell inherits the +e
    set +e
    (
      set -e
      trap t_cleanup EXIT
      t_setup
      "$fn"
    )
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then
      pass=$((pass + 1))
    else
      failed=$((failed + 1))
      echo "$suite: $fn failed"
    fi
  done
  echo "$suite: $pass passed, $failed failed"
  exit "$failed"
}
