#!/usr/bin/env bash
# Writes this repository's own copies of the shared files it uses as a target
# would: the workflows it runs, rendered with no values, as for a repository no
# target names, and tool-versions.yml, dependabot.yml and .gitignore, rendered
# for `repo=ci-shared`. They are copies, not symlinks into files/ like the lint
# configs and actions: a template's markers must not reach them, Actions does
# not run a symlinked workflow, and git does not follow a symlinked .gitignore.
#
#   scripts/own_files.sh [--check]
#
# --check writes nothing and fails, naming each, when a copy is out of date.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# each path, then the key=value pairs it is rendered with
OWN=(
  .github/workflows/codeql.yml
  .github/workflows/link-check.yml
  .github/workflows/scorecard.yml
  ".github/workflows/tool-versions.yml repo=ci-shared"
  ".github/dependabot.yml repo=ci-shared"
  ".gitignore repo=ci-shared"
  "REUSE.toml repo=ci-shared"
)

stale=0
for row in "${OWN[@]}"; do
  read -r path vars <<<"$row"
  if [ "${1:-}" = --check ]; then
    # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
    if ! ci_render "$path" $vars | cmp -s - "$CI_SHARED_DIR/$path"; then
      echo "$path is out of date: run scripts/own_files.sh" >&2
      stale=$((stale + 1))
    fi
  else
    # shellcheck disable=SC2086 # as above
    ci_render "$path" $vars >"$CI_SHARED_DIR/$path"
  fi
done
exit "$stale"
