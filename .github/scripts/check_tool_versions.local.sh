# shellcheck shell=bash
# The ci-shared specifics for ./check_tool_versions.sh, which sources this file (the hook contract is
# in that script's header). Nothing here runs on its own.

# No images here.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_IMAGE_GLOBS=''

# The Markdown tools' npm manifest, the shared copy every target receives.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_MANIFESTS='npm|.github/package.json'

# The run above reads this repository's own workflows and actions; `grep -r` does not follow the
# symlinks into files/, so the shared copies get a run of their own, rooted there, against this
# repository's tools.txt.
function ci_local_checks() {
  echo "## The shared copies (files/)"
  echo
  CI_TOOLS_TXT="$PWD/.github/actions/setup-tool/tools.txt" files/.github/scripts/check_tool_versions.sh
}
