#!/usr/bin/env bash
# tests/coverage.py: each rule that judges a statement from kcov's lines, the
# figures it prints, and its exit status.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# t.sh, and a kcov report of it: line 7 is not counted, so `v=3` is judged as
# the next statement; `echo in` sits in a substitution on an uncounted line,
# so as `z=...`, which a later line of its span shows ran; `t=5`, the last, is
# not counted at all.
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
  cat >"$T/cobertura.xml" <<'EOF'
<coverage><packages><package><classes>
<class filename="/elsewhere/t.sh"><lines>
<line number="1" hits="1"/><line number="2" hits="1"/><line number="3" hits="0"/>
<line number="4" hits="0"/><line number="5" hits="1"/><line number="6" hits="0"/>
<line number="8" hits="1"/><line number="9" hits="1"/><line number="10" hits="1"/>
</lines></class>
</classes></package></packages></coverage>
EOF
}

test_judges_each_statement() {
  fixture
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/cobertura.xml" "$T/t.sh" "$T/empty.sh"
  t_rc 1
  t_file "$T/out" "$(
    cat <<EOF
$T/t.sh: 9/11 statements (81.8%)
  $T/t.sh:6: not run
  $T/t.sh:12: not seen by kcov
$T/empty.sh: 0/0 statements (0.0%)
EOF
  )"
}

test_adds_up_several_reports() {
  fixture
  cat >"$T/more.xml" <<'EOF'
<coverage><packages><package><classes>
<class filename="t.sh"><lines><line number="6" hits="1"/><line number="12" hits="1"/></lines></class>
</classes></package></packages></coverage>
EOF
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/cobertura.xml" "$T/more.xml" "$T/t.sh" "$T/empty.sh"
  t_rc 0
  t_file "$T/out" "$(printf '%s\n' "$T/t.sh: 11/11 statements (100.0%)" "$T/empty.sh: 0/0 statements (0.0%)")"
}

test_needs_a_report_and_a_script() {
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/cobertura.xml"
  t_rc 1
  t_out "Statement coverage of shell scripts from kcov runs"
  t_run python3 -I "$TESTS_DIR/coverage.py" "$T/t.sh"
  t_rc 1
  t_out "Statement coverage of shell scripts from kcov runs"
}

t_main
