#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/sync_local.sh: copies files/ into checkouts beside the tree,
# templates rendered, modes kept, uncommitted edits left alone.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# one target, `a`, receiving a plain file, an executable and a template
fixture() {
  echo plain | t_shared plain.txt
  printf '#!/bin/sh\necho hi\n' | t_shared bin/run.sh x
  printf 'lang: __language__\n# shared:if language\ntyped\n# shared:endif\n' | t_shared tpl.yml
  t_target a dev plain.txt bin/run.sh tpl.yml
  t_toml a <<'EOF'
[templates."tpl.yml"]
language = "rust"
EOF
}

test_copies_renders_and_keeps_modes() {
  fixture
  t_checkout a
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 0
  t_out "a: plain.txt updated" "a: 3 file(s) updated"
  t_file "$T/a/plain.txt" plain
  t_file "$T/a/tpl.yml" "$(printf 'lang: rust\ntyped')"
  [ -x "$T/a/bin/run.sh" ] || t_fail "run.sh lost its executable bit"
  [ ! -x "$T/a/plain.txt" ] || t_fail "plain.txt became executable"

  # in line now: a second run changes nothing, and --check agrees
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 0
  t_out "a: 0 file(s) updated"
  t_run "$SCRIPTS/sync_local.sh" --check
  t_rc 0
  t_no_out differs
}

test_renders_markdown_markers_and_value_conditions() {
  fixture
  cat <<'EOF' | t_shared tpl.md
<!-- shared:if repo=a -->
only a
<!-- shared:endif -->
<!-- shared:unless repo=a -->
not a
<!-- shared:endif -->
# shared:if repo=b
b
# shared:endif
hello __greeting__
EOF
  t_target a dev tpl.md
  t_toml a <<'EOF'
[templates."tpl.md"]
repo = "a"
greeting = "good morning"
EOF
  t_checkout a
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 0
  t_file "$T/a/tpl.md" "$(printf 'only a\nhello good morning')"
}

test_a_template_value_with_a_percent_is_invalid() {
  fixture
  t_toml a <<'EOF'
[templates."plain.txt"]
share = "50%"
EOF
  t_checkout a
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 1
  t_out "templates.'plain.txt'.share must be a string of single-spaced words without %, & or \\"
  [ ! -f "$T/a/plain.txt" ] || t_fail "a copy was made"
}

test_check_reports_each_difference_and_writes_nothing() {
  fixture
  t_checkout a "plain.txt=stale"
  t_run "$SCRIPTS/sync_local.sh" --check "$T"
  t_rc 3
  t_out "a: plain.txt differs" "a: bin/run.sh differs" "a: tpl.yml differs"
  t_no_out "updated"
  t_file "$T/a/plain.txt" stale
}

test_a_mode_difference_alone_is_a_difference() {
  fixture
  t_checkout a "plain.txt=plain"
  chmod +x "$T/a/plain.txt"
  t_git "$T/a" commit -qam mode
  t_run "$SCRIPTS/sync_local.sh"
  t_out "a: plain.txt updated"
  [ ! -x "$T/a/plain.txt" ] || t_fail "plain.txt kept its executable bit"
}

test_leaves_uncommitted_changes_alone() {
  fixture
  t_checkout a "plain.txt=old"
  echo edited >"$T/a/plain.txt"
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 1
  t_out "a: plain.txt has uncommitted changes, left alone" "a: 2 file(s) updated"
  t_file "$T/a/plain.txt" edited
}

test_skips_a_missing_checkout() {
  fixture
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 0
  t_out "a: no checkout at $T/a, skipped"
}

test_exit_status_is_capped_at_255() {
  local i paths=()
  for i in $(seq 1 260); do
    echo "$i" | t_shared "f$i"
    paths+=("f$i")
  done
  t_target a dev "${paths[@]}"
  t_checkout a
  t_run "$SCRIPTS/sync_local.sh" --check
  t_rc 255
}

test_an_invalid_config_stops_before_any_copy() {
  fixture
  t_checkout a
  t_target b dev missing.txt
  t_run "$SCRIPTS/sync_local.sh"
  t_rc 1
  t_out "missing.txt is listed but files/missing.txt does not exist"
  [ ! -e "$T/a/plain.txt" ] || t_fail "copied despite the invalid config"
}

t_main
