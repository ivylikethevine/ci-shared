#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scratch/near_census.py: groups each path's copies across the checkouts,
# skips what --min and files/ rule out, scores each copy against the largest
# group's, and with --normalize ignores the project names.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# say-hi, sharerr-rs and zzz (no maturity rank) are checked out; nogit has no
# checkout. same.txt is shared already, solo.txt held once, gone.txt tracked
# but deleted, bin.dat binary and different in each.
fixture() {
  echo same | t_shared same.txt
  t_target say-hi dev
  t_target sharerr-rs dev
  t_target zzz dev
  t_target nogit dev
  t_checkout say-hi same.txt=same solo.txt=solo gone.txt=gone \
    diff.txt="$(printf 'a\nb\nc')" name.txt="hello say-hi"
  t_checkout sharerr-rs same.txt=same diff.txt="$(printf 'a\nB\nc')" name.txt="hello sharerr"
  t_checkout zzz diff.txt="$(printf 'a\nb\nc')"
  rm "$T/say-hi/gone.txt"
  printf '\377\000' >"$T/say-hi/bin.dat"
  printf '\376\001' >"$T/sharerr-rs/bin.dat"
  t_git "$T/say-hi" add bin.dat
  t_git "$T/sharerr-rs" add bin.dat
}

census() {
  t_run "$REPO_DIR/scratch/near_census.py" "$@"
}

test_scores_each_copy_against_the_largest_group() {
  fixture
  census
  t_rc 0
  t_file "$T/out" "$(
    cat <<'EOF'
bin.dat
  5d98346  say-hi  [reference, 1 lines]
  b3edade  sharerr-rs  [binary]
diff.txt
  de98044  say-hi zzz  [reference, 3 lines]
  7be73ce  sharerr-rs  [1 lines differ of 3, ratio 0.67]
name.txt
  52340e8  say-hi  [reference, 1 lines]
  44f8593  sharerr-rs  [1 lines differ of 1, ratio 0.00]
EOF
  )"
}

test_normalize_all_min_and_named_repos() {
  fixture
  census --normalize --all --min 2 "$T" sharerr-rs say-hi nogit
  t_rc 0
  # names folded, name.txt is one group; bin.dat, not text, is compared as it is
  t_file "$T/out" "$(
    cat <<'EOF'
bin.dat
  da33e41  say-hi  [reference, 1 lines]
  1b6dae7  sharerr-rs  [binary]
diff.txt
  3ca69e8  say-hi  [reference, 3 lines]
  6c693ec  sharerr-rs  [1 lines differ of 3, ratio 0.67]
name.txt
  ed533ff  say-hi sharerr-rs  [reference, 1 lines]
same.txt (files/)
  2c985b1  say-hi sharerr-rs  [reference, 1 lines]
EOF
  )"
  census --min 3
  t_rc 0
  t_file "$T/out" "$(printf 'diff.txt\n  de98044  say-hi zzz  [reference, 3 lines]\n  7be73ce  sharerr-rs  [1 lines differ of 3, ratio 0.67]')"
}

t_main
