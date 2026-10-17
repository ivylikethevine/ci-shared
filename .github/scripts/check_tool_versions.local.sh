# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# The ci-shared specifics for ./check_tool_versions.sh, which sources this file (the hook contract is
# in that script's header). Nothing here runs on its own.

# No images here.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_IMAGE_GLOBS=''

# The Markdown tools' npm manifest, the shared copy every target receives.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_MANIFESTS='npm|.github/package.json'

# The shared workflows and actions as well: `grep -r` does not follow this repository's symlinks
# into files/, and files/.github/workflows holds templates no symlink reaches.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_ACTION_DIRS='.github files/.github'
