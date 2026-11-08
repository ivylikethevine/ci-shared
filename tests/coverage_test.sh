#!/usr/bin/env bash
# tests/coverage.py: each rule that judges a statement from bashcov's lines,
# the figures it prints, and its exit status.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# t.sh, and a bashcov resultset of it: line 7 is not counted, so `v=3` is
# judged as the next statement; `echo in` sits in a substitution on an
# uncounted line, so as `z=...`, which a later line of its span shows ran;
# `t=5`, the last, is not counted at all. A copy of t.sh elsewhere, every line
# hit, credits nothing.
fixture() {
  cat >"$T/t.sh" <<'EOF'
x=1
y="$(echo hi)"
z="$(
  echo in
)"
w=2
v=3
u=4
if true; then
  b=2
fi
t=5
EOF
  printf '# only a comment\n' >"$T/empty.sh"
  cat >"$T/one.json" <<EOF
{"run_test.sh": {"coverage": {
  "$T/t.sh": {"lines": [1, 1, 0, 0, 1, 0, null, 1, 1, 1, null, null]},
  "/elsewhere/t.sh": {"lines": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]}
}, "timestamp": 1}}
EOF
}

test_judges_each_statement() {
  fixture
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/one.json" "$T/t.sh" "$T/empty.sh"
  t_rc 1
  t_file "$T/out" - <<EOF
$T/t.sh: 9/11 statements (81.8%)
  $T/t.sh:6: not run
  $T/t.sh:12: not seen by bashcov
$T/empty.sh: 0/0 statements (0.0%)
EOF
}

test_adds_up_several_resultsets_and_runs() {
  fixture
  cat >"$T/more.json" <<EOF
{"a": {"coverage": {"$T/t.sh": {"lines": [null, null, null, null, null, 1]}}},
 "b": {"coverage": {"$T/t.sh": {"lines": [null, null, null, null, null, null, null, null, null, null, null, 1]}}}}
EOF
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/one.json" "$T/more.json" "$T/t.sh" "$T/empty.sh"
  t_rc 0
  t_file "$T/out" "$(printf '%s\n' "$T/t.sh: 11/11 statements (100.0%)" "$T/empty.sh: 0/0 statements (0.0%)")"
}

test_needs_a_resultset_and_a_script() {
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/one.json"
  t_rc 1
  t_out "Statement coverage of shell scripts from bashcov runs"
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/t.sh"
  t_rc 1
  t_out "Statement coverage of shell scripts from bashcov runs"
}

t_main
