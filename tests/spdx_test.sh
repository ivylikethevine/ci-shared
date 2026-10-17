#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/spdx.sh: adds the license comment where each kind of file takes it,
# skips symlinks, license texts, JSON and files that have one, and --check
# fails while any file lacks it.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# REUSE-IgnoreStart
# A tracked file of each kind, an untracked one, a symlink, license texts and
# JSON.
fixture() {
  local d="$T/tree"
  printf '#!/usr/bin/env bash\ntrue\n' >"$d/run.sh"
  chmod +x "$d/run.sh"
  printf 'name: x\n' >"$d/a.yml"
  printf '# Title\n' >"$d/README.md"
  printf '# SPDX-License-Identifier: MIT\nkey = 1\n' >"$d/done.toml"
  printf '# MIT License\n' >"$d/LICENSE.md"
  mkdir -p "$d/LICENSES" "$d/files"
  printf '# MIT License\n' >"$d/files/LICENSE.md"
  printf 'MIT License\n' >"$d/LICENSES/MIT.txt"
  printf '{}\n' >"$d/data.json"
  ln -s a.yml "$d/link.yml"
  t_git "$d" init -q
  t_git "$d" add -A
  printf 'name: y\n' >"$d/untracked.yml"
}

test_adds_the_comment_where_each_file_takes_it() {
  fixture
  t_run "$SCRIPTS/spdx.sh"
  t_rc 0
  t_out "run.sh: added" "a.yml: added" "README.md: added"
  t_no_out "done.toml" "link.yml" "LICENSE" ".json" "untracked.yml"
  t_file "$T/tree/run.sh" "$(printf '#!/usr/bin/env bash\n# SPDX-License-Identifier: MIT\ntrue')"
  [ -x "$T/tree/run.sh" ] || t_fail "run.sh lost its mode"
  t_file "$T/tree/a.yml" "$(printf '# SPDX-License-Identifier: MIT\nname: x')"
  t_file "$T/tree/README.md" "$(printf '<!-- SPDX-License-Identifier: MIT -->\n\n# Title')"
  [ -L "$T/tree/link.yml" ] || t_fail "link.yml is no longer a symlink"
  t_file "$T/tree/LICENSE.md" "# MIT License"
  t_file "$T/tree/files/LICENSE.md" "# MIT License"
  t_file "$T/tree/LICENSES/MIT.txt" "MIT License"
  t_run "$SCRIPTS/spdx.sh" --check
  t_rc 0
}

test_check_fails_while_a_file_lacks_it() {
  fixture
  t_run "$SCRIPTS/spdx.sh" --check
  t_rc 1
  t_out "a.yml lacks an SPDX license comment: run scripts/spdx.sh"
  t_file "$T/tree/a.yml" "name: x"
}

# REUSE-IgnoreEnd

t_main
