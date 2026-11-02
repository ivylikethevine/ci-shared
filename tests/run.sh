#!/usr/bin/env bash
# Runs every tests/*_test.sh, or those named, side by side (T_JOBS at a time,
# tests/parallel.sh), and exits with the number of suites that failed.
#
#   tests/run.sh [SUITE...]     e.g. tests/run.sh sync_local census
#
# Needs bash 4.3+, git, jq and Python 3.11+.
set -uo pipefail

dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./parallel.sh
source "$dir/parallel.sh"
suites=()
if [ $# -gt 0 ]; then
  for s; do suites+=("${s%_test.sh}"); done
else
  for s in "$dir"/*_test.sh; do
    s="$(basename "$s")"
    suites+=("${s%_test.sh}")
  done
fi

run_one() {
  bash "$dir/$1_test.sh"
}

run_parallel "${suites[@]}"
echo "$((${#suites[@]} - FAILED)) of ${#suites[@]} suite(s) passed"
exit "$FAILED"
