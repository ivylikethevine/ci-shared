#!/usr/bin/env bash
# scripts/stale_pins.sh and scripts/bump_pins.sh: a target's own workflows and
# actions, the files the sync does not deliver, against the pins files/ uses.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OLD=1111111111111111111111111111111111111111
NEW=2222222222222222222222222222222222222222
OTHER=3333333333333333333333333333333333333333

# files/ pins act@NEW and, two ways, two@; target a receives shared.yml and owns
# ci.yml (act behind, one current, ext which files/ does not pin, two) and an
# action (act behind); b has no .github at all
pins_fixture() {
  printf 'jobs:\n  x:\n    steps:\n      - uses: act/one@%s # v2\n      - uses: two/x@%s # v1\n' "$NEW" "$OLD" |
    t_shared .github/workflows/shared.yml
  printf '      - uses: two/x@%s # v2\n' "$NEW" | t_shared .github/workflows/other.yml
  t_target a dev .github/workflows/shared.yml
  t_target b dev
  mkdir -p "$T/a/.github/workflows" "$T/a/.github/actions/setup" "$T/b"
  printf '      - uses: act/one@%s # v1\n' "$OLD" >"$T/a/.github/workflows/shared.yml"
  cat >"$T/a/.github/workflows/ci.yml" <<EOF
jobs:
  x:
    steps:
      - uses: act/one@$OLD # v1
      - uses: ext/tool@$OLD # v1
      - uses: two/x@$OLD # v1
      - uses: ./.github/actions/setup
  y:
    steps:
      - uses: act/one@$NEW # v2
EOF
  printf '    - uses: act/one@%s # v1\n' "$OLD" >"$T/a/.github/actions/setup/action.yml"
}

test_stale_lists_own_pins_behind_files() {
  pins_fixture
  t_run "$SCRIPTS/stale_pins.sh"
  t_rc 1
  t_out "files/ pins two/x 2 ways; left out"
  t_match "$T/out" \
    "^a	\\.github/actions/setup/action\\.yml:1	act/one@$OLD	act/one@$NEW # v2\$" \
    "^a	\\.github/workflows/ci\\.yml:4	act/one@$OLD	act/one@$NEW # v2\$"
  # the received file, the current pin, and the actions files/ does not settle
  t_no_out "shared.yml" "ci.yml:10" "ext/tool" "two/x@$OLD	"
  [ "$(grep -c '^a	' "$T/out")" = 2 ] || t_fail "wanted two rows"
}

test_stale_is_quiet_when_current() {
  pins_fixture
  t_run "$SCRIPTS/stale_pins.sh" b
  t_rc 0
  t_eq "$(cat "$T/out")" "files/ pins two/x 2 ways; left out" "the output"
}

test_stale_names_a_missing_checkout() {
  pins_fixture
  t_target c dev
  t_run "$SCRIPTS/stale_pins.sh" c a
  t_rc 2
  t_out "stale_pins: no checkout of c at $T/c" "act/one@$OLD"
}

test_stale_refuses_an_unknown_target() {
  pins_fixture
  t_run "$SCRIPTS/stale_pins.sh" nope
  t_rc 1
  t_out "repos/ has no target nope"
}

test_bump_moves_own_pins_to_files() {
  pins_fixture
  t_run "$SCRIPTS/bump_pins.sh" a
  t_rc 0
  t_out "a	.github/actions/setup/action.yml	act/one" "a	.github/workflows/ci.yml	act/one"
  t_in "$T/a/.github/workflows/ci.yml" "act/one@$NEW # v2" "ext/tool@$OLD # v1" "two/x@$OLD # v1"
  t_not_in "$T/a/.github/workflows/ci.yml" "act/one@$OLD"
  t_in "$T/a/.github/workflows/shared.yml" "act/one@$OLD # v1"
  t_run "$SCRIPTS/stale_pins.sh" a
  t_rc 0
}

test_bump_takes_pins_for_other_actions() {
  pins_fixture
  t_run "$SCRIPTS/bump_pins.sh" a "ext/tool@$OTHER # v3"
  t_rc 0
  t_file "$T/out" "a	.github/workflows/ci.yml	ext/tool"
  t_in "$T/a/.github/workflows/ci.yml" "ext/tool@$OTHER # v3" "act/one@$OLD # v1"
}

test_bump_refuses_bad_arguments() {
  pins_fixture
  t_run "$SCRIPTS/bump_pins.sh"
  t_rc 2
  t_out "usage: scripts/bump_pins.sh NAME [PIN...]"
  t_run "$SCRIPTS/bump_pins.sh" a "ext/tool@$OTHER"
  t_rc 2
  t_out "bump_pins: 'ext/tool@$OTHER' is not 'owner/action@<40 hex> # <version>'"
  t_target c dev
  t_run "$SCRIPTS/bump_pins.sh" c
  t_rc 2
  t_out "bump_pins: no checkout of c at $T/c"
}

t_main
