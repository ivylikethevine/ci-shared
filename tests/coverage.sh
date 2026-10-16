#!/usr/bin/env bash
# Runs every suite under kcov and fails unless every statement of scripts/*.sh
# ran; tests/coverage.py says how a statement is judged from kcov's lines.
# The checks workflow's coverage job runs it.
#
#   tests/coverage.sh [OUT]
#
# OUT, which must not exist yet (kcov adds to an earlier run's counts), gets
# kcov's report; the default is a fresh temporary directory. Needs kcov and
# shfmt on PATH, as tools.txt pins them, besides what tests/run.sh needs.
set -euo pipefail

repo="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ $# -gt 0 ]; then
  out=$1
  if [ -e "$out" ]; then
    echo "coverage: $out exists; kcov would add to its counts" >&2
    exit 2
  fi
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/ci-shared-coverage.XXXXXX")"
fi

kcov --include-path="$repo/scripts" --bash-parse-files-in-dir="$repo/scripts" "$out" "$repo/tests/run.sh"
echo "report: $out/run.sh/index.html"
python3 -I "$repo/tests/coverage.py" "$out/run.sh/cobertura.xml" "$repo"/scripts/*.sh
