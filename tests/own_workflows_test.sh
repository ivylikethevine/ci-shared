#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/own_workflows.sh: writes this repository's copies of the shared
# workflows it runs, rendered with no values, and --check fails when one is
# stale.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fixture() {
  mkdir -p "$T/tree/.github/workflows"
  printf 'name: CodeQL\n# shared:if language\nlang: __language__\n# shared:endif\nactions: true\n' |
    t_shared .github/workflows/codeql.yml
  echo 'name: Link check' | t_shared .github/workflows/link-check.yml
  echo 'name: Scorecard' | t_shared .github/workflows/scorecard.yml
}

test_writes_each_copy_rendered_and_check_agrees() {
  fixture
  t_run "$SCRIPTS/own_workflows.sh"
  t_rc 0
  t_file "$T/tree/.github/workflows/codeql.yml" $'name: CodeQL\nactions: true'
  t_file "$T/tree/.github/workflows/link-check.yml" 'name: Link check'
  t_file "$T/tree/.github/workflows/scorecard.yml" 'name: Scorecard'
  t_run "$SCRIPTS/own_workflows.sh" --check
  t_rc 0
}

test_check_names_each_stale_copy() {
  fixture
  "$SCRIPTS/own_workflows.sh"
  echo 'name: Scorecard v2' | t_shared .github/workflows/scorecard.yml
  rm "$T/tree/.github/workflows/codeql.yml"
  t_run "$SCRIPTS/own_workflows.sh" --check
  t_rc 2
  t_out ".github/workflows/codeql.yml is out of date: run scripts/own_workflows.sh" \
    ".github/workflows/scorecard.yml is out of date"
  t_no_out "link-check.yml"
}

t_main
