#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/census.sh: groups the CI files checkouts share by content, marks the
# copies files/ renders to, and --drift keeps only paths whose copies differ.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

blob() {
  printf '%s\n' "$1" | git hash-object --stdin | cut -c1-7
}

# a holds no CI file; b, c and d share .editorconfig (d's drifted); b and c
# receive a template with their own values, which d holds unrendered for it
# (no values), so d's copy matches b's blob but not files/; lychee.toml is b's
# alone
fixture() {
  echo shared | t_shared .editorconfig
  printf 'v: __v__\n' | t_shared .github/t.yml
  for n in a b c d; do t_target "$n" dev; done
  t_target b dev .editorconfig .github/t.yml
  t_toml b <<'EOF'
[templates.".github/t.yml"]
v = "1"
EOF
  t_target c dev .github/t.yml
  t_toml c <<'EOF'
[templates.".github/t.yml"]
v = "2"
EOF
  t_checkout a "README.md=hi"
  t_checkout b ".editorconfig=shared" ".github/t.yml=v: 1" "lychee.toml=x" "src/main.rs=x"
  t_checkout c ".editorconfig=shared" ".github/t.yml=v: 2" ".github/gone.yml=x"
  rm "$T/c/.github/gone.yml"
  t_checkout d ".editorconfig=drifted" ".github/t.yml=v: 1"
}

test_groups_copies_and_marks_files_matches() {
  fixture
  t_run "$SCRIPTS/census.sh"
  t_rc 0
  # awk prints a path's groups in no set order
  t_eq "$(sort "$T/out")" "$(
    sort <<EOF
.editorconfig
  $(blob drifted) 100644  d
  $(blob shared) 100644 = files/  b c
.github/t.yml
  $(blob 'v: 1') 100644 = files/  b
  $(blob 'v: 1') 100644  d
  $(blob 'v: 2') 100644 = files/  c
EOF
  )" "the census"
}

test_drift_keeps_paths_with_several_copies() {
  fixture
  t_checkout e ".editorconfig=shared" "lychee.toml=x"
  t_target e dev
  t_git "$T/b" rm -q .editorconfig
  t_git "$T/b" commit -qm drop
  t_checkout b2 "lychee.toml=x"
  t_target b2 dev
  t_run "$SCRIPTS/census.sh" --drift "$T"
  t_rc 0
  t_out .editorconfig .github/t.yml
  t_no_out lychee.toml
}

t_main
