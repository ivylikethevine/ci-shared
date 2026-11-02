# shellcheck shell=bash
# Sourced by tests/run.sh and tests/coverage.sh: runs the suites side by side.

# run_parallel <name...> - calls the caller's `run_one <name>` for each, at most
# T_JOBS at a time (default the CPUs, at most 4), prints each output whole in the
# order given, and sets FAILED to how many failed
run_parallel() {
  local logs name running=0 limit
  limit="${T_JOBS:-$(nproc 2>/dev/null || echo 2)}"
  [ -n "${T_JOBS:-}" ] || [ "$limit" -le 4 ] || limit=4
  logs="$(mktemp -d "${TMPDIR:-/tmp}/ci-shared-parallel.XXXXXX")"
  for name; do
    if [ "$running" -ge "$limit" ]; then
      wait -n || true
      running=$((running - 1))
    fi
    (
      rc=0
      run_one "$name" >"$logs/$name.log" 2>&1 || rc=$?
      echo "$rc" >"$logs/$name.rc"
    ) &
    running=$((running + 1))
  done
  wait || true
  FAILED=0
  for name; do
    cat "$logs/$name.log"
    [ "$(cat "$logs/$name.rc")" = 0 ] || FAILED=$((FAILED + 1))
  done
  case $logs in */ci-shared-parallel.??????) rm -r -- "$logs" ;; esac
}
