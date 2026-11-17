#!/usr/bin/env bash
# scripts/mise_pins.sh: the shared mise file, as each target receiving it
# renders it, agrees with that target's tools.txt rows, and each kind of
# difference prints its own line.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TOOLS=.github/actions/setup-tool/tools.txt
MISE=.config/mise/conf.d/ci-tools.toml

# a tools.txt template whose `b` row only target `a` receives, and a mise file
# holding the rows as `a` renders them
fixture() {
  t_shared "$TOOLS" <<'EOF'
# name|pin|kind|url|verify|check|tag-prefix|sha256
one|1.0|raw|u|v|c||h
freeze|0.2|raw|u|v|c||h
deb|2.0|raw|u|v|c||h
# shared:if repo=a
b|3.0|raw|u|v|c||h
# shared:endif
EOF
  t_shared "$MISE" <<'EOF'
# Not here:
#   apt: deb
[settings]
x = "9"

[tools]
# a comment
one = "1.0"
"aqua:o/freeze" = "0.2"
b = "3.0"
EOF
  t_target a main "$TOOLS" "$MISE"
}

test_a_mise_file_matching_its_rows_passes() {
  fixture
  # a target receiving tools.txt alone is no concern of the check
  t_target other main "$TOOLS"
  t_run "$SCRIPTS/mise_pins.sh"
  t_rc 0
  [ ! -s "$T/out" ] || t_fail "printed $(cat "$T/out")"
}

test_each_difference_is_named() {
  fixture
  t_shared "$MISE" <<'EOF'
#   apt: deb ghost
[tools]
one = "1.1"
"aqua:o/freeze" = "0.2"
stray = "1"
EOF
  t_run "$SCRIPTS/mise_pins.sh"
  t_rc 4
  t_out 'a: one 1.1 is not the tools.txt pin 1.0' \
    'a: stray is no tools.txt row' \
    'a: tools.txt pins b 3.0, which the mise file neither lists nor names under apt:' \
    'a: apt: names ghost, no tools.txt row'
}

test_a_row_another_target_lacks_is_its_own() {
  fixture
  # `b` is a's row alone, so z's mise file listing it is a stray
  t_target z main "$TOOLS" "$MISE"
  t_run "$SCRIPTS/mise_pins.sh"
  t_rc 1
  t_out 'z: b is no tools.txt row'
  t_no_out 'a: '
}

test_a_mise_file_without_tools_txt_fails() {
  fixture
  t_target lone main "$MISE"
  t_run "$SCRIPTS/mise_pins.sh"
  t_rc 1
  t_out "lone: receives $MISE but not $TOOLS"
}

t_main
