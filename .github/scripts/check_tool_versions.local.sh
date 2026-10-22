# shellcheck shell=bash
# The ci-shared specifics for ./check_tool_versions.sh, which sources this file (the hook contract is
# in that script's header). Nothing here runs on its own.

# No images here.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_IMAGE_GLOBS=''

# The pins inside shared files that no roster or manifest names, so the drift
# shows where the edit is made. Each target's own hook checks its rendered copy
# of _config.yml; this row checks the template. advisories.yml's
# `python-version` is moved by hand: PyPI has no feed for CPython itself.
#   just-the-docs  the Pages theme, files/_config.yml's `remote_theme:`
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_WORKFLOW_ROSTER='just-the-docs|files/_config.yml|remote_theme: just-the-docs/just-the-docs@v\([0-9][0-9.]*\)|github:just-the-docs/just-the-docs|'

# The Markdown tools' npm manifest, the shared copy every target receives, and
# the Python dev tools' pip-compile input.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_MANIFESTS='npm|.github/package.json
pip|requirements-dev.in'

# The shared workflows and actions as well: `grep -r` does not follow this repository's symlinks
# into files/, and files/.github/workflows holds templates no symlink reaches.
# shellcheck disable=SC2034 # read by check_tool_versions.sh
CI_ACTION_DIRS='.github files/.github'
