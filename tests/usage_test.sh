#!/usr/bin/env bash
# scripts/usage.sh: writes USAGE.md's table of files against targets and the
# template values, and --check fails when it is stale.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fixture() {
  echo x | t_shared .editorconfig
  echo x | t_shared .github/a-much-longer-shared-path.yml
  t_target alpha dev .editorconfig .github/a-much-longer-shared-path.yml
  t_target b dev .editorconfig
}

test_writes_the_table_and_check_agrees() {
  fixture
  t_run "$SCRIPTS/usage.sh"
  t_rc 0
  t_file "$T/tree/USAGE.md" "$(
    cat <<'EOF'
# Usage

Which repositories receive each shared file, written by
`scripts/usage.sh` from `repos/`; run it after changing a file list there.

| File                                    | alpha | b | Repos |
| --------------------------------------- | ----- | - | ----- |
| `.editorconfig`                         | x     | x | 2     |
| `.github/a-much-longer-shared-path.yml` | x     |   | 1     |
| **Files per repository**                | 2     | 1 | 2     |
EOF
  )"
  t_run "$SCRIPTS/usage.sh" --check
  t_rc 0
}

test_lists_template_values() {
  fixture
  t_toml b <<'EOF'
[templates.".editorconfig"]
indent = "4"
EOF
  t_run "$SCRIPTS/usage.sh"
  t_rc 0
  # shellcheck disable=SC2016 # literal text
  grep -qxF -- '- `.editorconfig` in b: `indent=4`' "$T/tree/USAGE.md" || t_fail "no template values in $(cat "$T/tree/USAGE.md")"
  grep -qxF '## Template values' "$T/tree/USAGE.md" || t_fail "no template values heading"
}

test_check_fails_when_stale() {
  fixture
  t_run "$SCRIPTS/usage.sh"
  t_target b dev
  t_run "$SCRIPTS/usage.sh" --check
  t_rc 1
  t_out "USAGE.md is out of date: run scripts/usage.sh"
}

t_main
