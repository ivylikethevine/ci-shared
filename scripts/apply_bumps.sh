#!/usr/bin/env bash
# Edits what the version check reported behind: the files/ pins and this
# repository's own, which the sync then carries to every target.
#
#   CI_FIX_LIST=fixes .github/scripts/check_tool_versions.sh
#   scripts/apply_bumps.sh fixes
#
# Reads the check's CI_FIX_LIST lines. A tool's row takes its new pin and the
# sha256 of each asset it names, fetched here; an action's SHA and comment move
# in every workflow and action; an inline pin moves on the lines its regex
# matches; a manifest's version moves and its lock is regenerated, with npm or
# pip-compile, which are needed on PATH with curl and jq. Prints one Markdown
# line per bump for the pull request. A bump that cannot be made is annotated,
# printed and left as it is, and the others still land; exits with their number.
# shellcheck disable=SC2329 # the bump_* functions, and so the rest, run through an array
# shellcheck disable=SC2016 # awk's and jq's $vars, not the shell's
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ $# = 1 ] || {
  echo "usage: apply_bumps.sh <fix list>" >&2
  exit 2
}
list="$(cd -P "$(dirname "$1")" && pwd -P)/$(basename "$1")"
cd "$CI_SHARED_DIR"
ci_tmpdir

TOOLS=files/.github/actions/setup-tool/tools.txt
failed=0 pip=0
declare -A npm=()

# rewrite <file> <command...> - the file through the command, in place, so a
# symlink stays one; fails when the command does or nothing changed
rewrite() {
  local file=$1
  shift
  "$@" <"$file" >"$CI_TMP/new" || return 1
  if cmp -s "$CI_TMP/new" "$file"; then return 1; fi
  cat "$CI_TMP/new" >"$file"
}

# asset_sha <url> <version> <slug> - the sha256 of that asset
asset_sha() {
  local url="${1//%v/$2}"
  url="${url//%a/$3}"
  curl -sSfL "$url" | sha256sum | cut -d' ' -f1
}

# bump_tool <name> <pin> <due> - its tools.txt row: the pin, and the sha256
# column as the row spells it. An unchanged hash is the header's red flag.
bump_tool() {
  local name=$1 due=$3 row url sha entry key hex new=""
  row="$(awk -F'|' -v t="$name" '$1 == t { print; exit }' "$TOOLS")"
  [ -n "$row" ] || return 1
  IFS='|' read -r _ _ _ url _ _ _ sha <<<"$row"
  case "$sha" in
  *=*)
    for entry in ${sha//,/ }; do
      key="${entry%%=*}"
      hex="$(asset_sha "$url" "$due" "${key#*:}")" || return 1
      new="$new,$key=$hex"
    done
    new="${new#,}"
    ;;
  *) new="$(asset_sha "$url" "$due" "")" || return 1 ;;
  esac
  [ "$new" != "$sha" ] || return 1
  rewrite "$TOOLS" awk -F'|' -v OFS='|' -v t="$name" -v pin="$due" -v sha="$new" \
    '$1 == t { $2 = pin; $8 = sha } { print }'
}

# bump_action <owner/repo> <pin> <value> - every `uses:` of the action at that
# pin, its sub-paths too. <value> is the check's `@<sha> # v<version>`.
bump_action() {
  local repo="${1//./\\.}" pin="${2//./\\.}" value=$3 file any=1
  [ -n "$value" ] || return 1
  for file in .github/workflows/*.yml files/.github/workflows/*.yml files/.github/actions/*/action.yml; do
    if rewrite "$file" sed -E "s|(uses: $repo(/[^@ ]+)?)@[0-9a-f]{40} # v$pin\$|\1$value|"; then any=0; fi
  done
  return "$any"
}

# bump_inline <glob> <regex> <pin> <due> - the pin, on the lines of each file
# the regex matches
bump_inline() {
  local regex=$2 pin="${3//./\\.}" due=$4 file any=1
  while IFS= read -r file; do
    if rewrite "$file" sed -e "\\|$regex|s|$pin|$due|"; then any=0; fi
  done < <(compgen -G "$1" || true)
  return "$any"
}

# bump_npm <manifest> <name> <due> - the version wherever the manifest names it
bump_npm() {
  rewrite "$1" jq --arg n "$2" --arg v "$3" 'reduce ("dependencies", "devDependencies", "overrides") as $k (.;
    if .[$k] and (.[$k] | has($n)) then .[$k][$n] = $v else . end)' || return 1
  npm[$(dirname "$(realpath "$1")")]=1
}

# bump_pip <in file> <name> <pin> <due> - its `name==pin` line, the name as PyPI
# folds it (the check reports it folded)
bump_pip() {
  rewrite "$1" sed -E "s/^${2//-/[-_.]+}==${3//./\\.}(\$|[^0-9.])/$2==$4\1/I" || return 1
  pip=1
}

while IFS='|' read -r kind name pinned due value file regex; do
  case "$kind" in
  tool) bump=(bump_tool "$name" "$pinned" "$due") ;;
  action) bump=(bump_action "$name" "$pinned" "$value") ;;
  inline) bump=(bump_inline "$file" "$regex" "$pinned" "$due") ;;
  npm) bump=(bump_npm "$file" "$name" "$due") ;;
  pip) bump=(bump_pip "$file" "$name" "$pinned" "$due") ;;
  *) bump=(false) ;;
  esac
  if "${bump[@]}"; then
    echo "- \`$name\` $pinned to $due"
  else
    echo "::error title=bump $name::could not bump $kind $name from $pinned to $due; do it by hand" >&2
    echo "- \`$name\` $pinned to $due: **not bumped**, do it by hand"
    failed=$((failed + 1))
  fi
done <"$list"

# A lock's generated hashes from each manifest changed. Every requirements
# file, in order: requirements-dev.in reads requirements-coverage.in.
if [ "$pip" = 1 ]; then
  for file in requirements-*.in; do
    pip-compile --quiet --allow-unsafe --generate-hashes --strip-extras "$file" >&2
  done
fi
for dir in "${!npm[@]}"; do
  npm install --prefix "$dir" --package-lock-only --ignore-scripts --no-audit --no-fund >&2
done
"$CI_SCRIPTS_DIR/own_files.sh"
exit "$failed"
