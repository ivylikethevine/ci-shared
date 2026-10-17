#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs the checks this repository ships over the repository itself, files/
# included, with the shared configs: shellcheck and shfmt (.shellcheckrc,
# .editorconfig), actionlint, lint_workflows.sh, zizmor (.github/zizmor.yml),
# prettier and markdownlint (.prettierrc.yaml, .markdownlint.yaml), then each
# template as every target receives it: actionlint and lint_workflows.sh for a
# workflow, markdownlint for Markdown, prettier for what it has a parser for,
# and no `__key__` left that a target sets. USAGE.md must be current and every tracked file carry an
# SPDX license comment. CI's checks workflow runs the same script.
#
#   scripts/check.sh
#
# Needs the tools.txt pins on PATH and `npm ci --prefix .github` once. A
# missing tool fails its check rather than skipping it. Exits with the number
# of checks that failed.
set -uo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$CI_SHARED_DIR" || exit 1

failed=0
run() {
  local name=$1
  shift
  echo "== $name"
  if "$@"; then
    echo "ok"
  else
    echo "::error title=$name::$name failed"
    failed=$((failed + 1))
  fi
}

scripts=()
while IFS= read -r f; do scripts+=("$f"); done < <(
  find scripts tests .github/scripts files -name '*.sh' -type f | LC_ALL=C sort
)
workflows=(.github/workflows/*.yml files/.github/workflows/*.yml)
bin=.github/node_modules/.bin
# zizmor reads GH_TOKEN itself for its online audits
offline=()
[ -n "${GH_TOKEN:-}" ] || offline=(--offline)

run shellcheck shellcheck -x "${scripts[@]}"
run shfmt shfmt -d "${scripts[@]}"
run actionlint actionlint "${workflows[@]}"
run lint-workflows .github/scripts/lint_workflows.sh "${workflows[@]}" files/.github/actions/*/action.yml
run zizmor zizmor --config .github/zizmor.yml ${offline[@]+"${offline[@]}"} .github/workflows files/.github
# A Markdown template's markers break the lists around them, and a JSON
# template's are not JSON, so the raw copies are linted rendered below instead
raw_prettier=(.) raw_markdownlint=('**/*.md' '#**/node_modules')
while IFS= read -r f; do
  ci_is_template "${f#files/}" || continue
  raw_prettier+=("!$f")
  case $f in *.md) raw_markdownlint+=("#$f") ;; esac
done < <(find files \( -name '*.md' -o -name '*.json' \) -type f | LC_ALL=C sort)
run prettier "$bin/prettier" --check "${raw_prettier[@]}"
run markdownlint "$bin/markdownlint-cli2" "${raw_markdownlint[@]}"
run usage "$CI_SCRIPTS_DIR/usage.sh" --check
run spdx "$CI_SCRIPTS_DIR/spdx.sh" --check

# Each template rendered for every target that receives it, so a placeholder or
# block that breaks only one repository's copy still fails here.
run config ci_load
rendered="$(mktemp -d "${TMPDIR:-/tmp}/ci-render.XXXXXX")"
trap 'case "$rendered" in */ci-render.??????) rm -r "$rendered" ;; esac' EXIT
templates=() workflows_rendered=() md_rendered=()
declare -A keys=()
while read -r slug _; do
  name="${slug#*/}"
  # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
  while read -r path vars; do
    [ -n "$vars" ] || ci_is_template "$path" || continue
    mkdir -p "$rendered/$name/$(dirname "$path")"
    ci_render "$path" $vars >"$rendered/$name/$path"
    templates+=("$rendered/$name/$path")
    case "$path" in
    .github/workflows/*) workflows_rendered+=("$rendered/$name/$path") ;;
    *.md) md_rendered+=("$rendered/$name/$path") ;;
    esac
    for kv in $vars; do keys[$path]="${keys[$path]:-} ${kv%%=*}"; done
  done < <(ci_targets "$name")
done < <(ci_repos)

# A `__key__` still in a rendering, for a key any target gives that path: a
# value a target forgot, or one used only inside a block another target keeps.
# shellcheck disable=SC2329 # run calls it by name
unrendered() {
  local f path key found=0
  for f in "${templates[@]}"; do
    path="${f#"$rendered"/*/}"
    for key in ${keys[$path]:-}; do
      if grep -qF "__${key}__" "$f"; then
        echo "${f#"$rendered"/} leaves __${key}__ unrendered"
        found=1
      fi
    done
  done
  [ "$found" = 0 ]
}

if [ ${#templates[@]} -gt 0 ]; then
  run unrendered unrendered
  # --ignore-unknown: a file prettier has no parser for (.gitattributes)
  run prettier-rendered "$bin/prettier" --check --config .prettierrc.yaml --ignore-unknown "${templates[@]}"
fi
if [ ${#workflows_rendered[@]} -gt 0 ]; then
  run actionlint-rendered actionlint "${workflows_rendered[@]}"
  run lint-workflows-rendered .github/scripts/lint_workflows.sh "${workflows_rendered[@]}"
fi
if [ ${#md_rendered[@]} -gt 0 ]; then
  run markdownlint-rendered "$bin/markdownlint-cli2" --config .markdownlint.yaml "${md_rendered[@]}"
fi

exit "$failed"
