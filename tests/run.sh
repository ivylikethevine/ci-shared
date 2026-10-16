#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs every tests/*_test.sh, or those named, and exits with the number of
# suites that failed.
#
#   tests/run.sh [SUITE...]     e.g. tests/run.sh sync_local census
#
# Needs bash, git, jq and Python 3.11+.
set -uo pipefail

dir="$(dirname "${BASH_SOURCE[0]}")"
suites=()
if [ $# -gt 0 ]; then
  for s; do suites+=("$dir/${s%_test.sh}_test.sh"); done
else
  suites=("$dir"/*_test.sh)
fi

failed=0
for s in "${suites[@]}"; do
  bash "$s" || failed=$((failed + 1))
done
echo "$((${#suites[@]} - failed)) of ${#suites[@]} suite(s) passed"
exit "$failed"
