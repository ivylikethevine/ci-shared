#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Writes this repository's own copies of the shared workflows it runs, each
# rendered from files/ with no values, as for a repository no target names.
# They are copies, not symlinks into files/ like the lint configs and actions:
# a template's markers must not reach a workflow, and Actions does not run a
# symlinked one.
#
#   scripts/own_workflows.sh [--check]
#
# --check writes nothing and fails, naming each, when a copy is out of date.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOWS=(codeql.yml link-check.yml scorecard.yml)

stale=0
for w in "${WORKFLOWS[@]}"; do
  path=".github/workflows/$w"
  if [ "${1:-}" = --check ]; then
    if ! ci_render "$path" | cmp -s - "$CI_SHARED_DIR/$path"; then
      echo "$path is out of date: run scripts/own_workflows.sh" >&2
      stale=$((stale + 1))
    fi
  else
    ci_render "$path" >"$CI_SHARED_DIR/$path"
  fi
done
exit "$stale"
