#!/usr/bin/env bash
# scripts/own_files.sh: writes this repository's copies of the shared files it
# uses, the workflows rendered with no values and dependabot.yml for
# `repo=ci-shared`, and --check fails when one is stale.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fixture() {
  mkdir -p "$T/tree/.github/workflows"
  printf 'name: CodeQL\n# shared:if language\nlang: __language__\n# shared:endif\nactions: true\n' |
    t_shared .github/workflows/codeql.yml
  echo 'name: Link check' | t_shared .github/workflows/link-check.yml
  echo 'name: Scorecard' | t_shared .github/workflows/scorecard.yml
  printf 'version: 2\n# shared:if repo=a\na: true\n# shared:endif\n# shared:if repo=ci-shared\nown: true\n# shared:endif\n' |
    t_shared .github/dependabot.yml
}

test_writes_each_copy_rendered_and_check_agrees() {
  fixture
  t_run "$SCRIPTS/own_files.sh"
  t_rc 0
  t_file "$T/tree/.github/workflows/codeql.yml" $'name: CodeQL\nactions: true'
  t_file "$T/tree/.github/workflows/link-check.yml" 'name: Link check'
  t_file "$T/tree/.github/workflows/scorecard.yml" 'name: Scorecard'
  t_file "$T/tree/.github/dependabot.yml" $'version: 2\nown: true'
  t_run "$SCRIPTS/own_files.sh" --check
  t_rc 0
}

test_check_names_each_stale_copy() {
  fixture
  "$SCRIPTS/own_files.sh"
  echo 'name: Scorecard v2' | t_shared .github/workflows/scorecard.yml
  rm "$T/tree/.github/workflows/codeql.yml"
  printf 'version: 2\n# shared:if repo=ci-shared\nown: false\n# shared:endif\n' | t_shared .github/dependabot.yml
  t_run "$SCRIPTS/own_files.sh" --check
  t_rc 3
  t_out ".github/workflows/codeql.yml is out of date: run scripts/own_files.sh" \
    ".github/workflows/scorecard.yml is out of date" ".github/dependabot.yml is out of date"
  t_no_out "link-check.yml"
}

t_main
