#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Adds an SPDX MIT license comment to each tracked file that lacks one: after
# the shebang, else on line 1 (`<!-- -->` in Markdown, `#` elsewhere).
# Symlinks are skipped (their targets are tracked too), as are files deleted
# from the working tree and license texts,
# which stay verbatim, and JSON, which has no comment syntax: REUSE.toml covers
# both.
#
#   scripts/spdx.sh [--check]
#
# --check writes nothing and fails when a file lacks the comment.
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check=0
[ "${1:-}" != --check ] || check=1
# REUSE-IgnoreStart
tag='SPDX-License-Identifier'
# REUSE-IgnoreEnd
spdx="$tag: MIT"

missing=0
while IFS= read -r -d '' path; do
  f="$CI_SHARED_DIR/$path"
  [ ! -L "$f" ] && [ -e "$f" ] || continue
  case "$path" in *.json | LICENSE* | */LICENSE*) continue ;; esac
  ! grep -q "$tag:" "$f" || continue
  missing=$((missing + 1))
  if [ "$check" = 1 ]; then
    echo "$path lacks an SPDX license comment: run scripts/spdx.sh"
    continue
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/ci-spdx.XXXXXX")"
  case "$path" in
  *.md) { printf '<!-- %s -->\n\n' "$spdx" && cat "$f"; } >"$tmp" ;;
  *) awk -v line="# $spdx" '
       NR == 1 && /^#!/ { print; print line; next }
       NR == 1 { print line }
       { print }
     ' "$f" >"$tmp" ;;
  esac
  cat "$tmp" >"$f" # keeps the file's mode
  rm "$tmp"
  echo "$path: added"
done < <(git -C "$CI_SHARED_DIR" ls-files -z)

[ "$check" = 0 ] || [ "$missing" = 0 ]
