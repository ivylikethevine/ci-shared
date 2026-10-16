#!/usr/bin/env bash
# Runs the checks this repository ships over the repository itself, files/
# included, with the shared configs: shellcheck and shfmt (.shellcheckrc,
# .editorconfig), actionlint, lint_workflows.sh, zizmor (.github/zizmor.yml), prettier and
# markdownlint (.prettierrc.yaml, .markdownlint.yaml), actionlint and
# lint_workflows.sh again over each template as every target receives it, and
# that USAGE.md is current. CI's checks workflow runs the same script.
#
#   scripts/check.sh
#
# Needs the tools.txt pins on PATH and `npm ci --prefix .github` once. A
# missing tool fails its check rather than skipping it. Exits with the number
# of checks that failed.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

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
  find scripts .github/scripts files -name '*.sh' -type f | LC_ALL=C sort
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
run prettier "$bin/prettier" --check .
run markdownlint "$bin/markdownlint-cli2" '**/*.md' '#**/node_modules'
run usage scripts/usage.sh --check

# Each template rendered for every target that receives it, so a placeholder or
# block that breaks only one repository's copy still fails here.
# shellcheck source=./lib.sh
source scripts/lib.sh
run config ci_load
rendered="$(mktemp -d "${TMPDIR:-/tmp}/ci-render.XXXXXX")"
trap 'case "$rendered" in */ci-render.??????) rm -r "$rendered" ;; esac' EXIT
templates=()
while read -r slug _; do
  name="${slug#*/}"
  # shellcheck disable=SC2086 # $vars is key=value words, split on purpose
  while read -r path vars; do
    case "$path" in .github/workflows/*) ;; *) continue ;; esac
    [ -n "$vars" ] || grep -q '# shared:' "files/$path" || continue
    mkdir -p "$rendered/$name/$(dirname "$path")"
    ci_render "$path" $vars >"$rendered/$name/$path"
    templates+=("$rendered/$name/$path")
  done < <(ci_targets "$name")
done < <(ci_repos)
if [ ${#templates[@]} -gt 0 ]; then
  run actionlint-rendered actionlint "${templates[@]}"
  run lint-workflows-rendered .github/scripts/lint_workflows.sh "${templates[@]}"
fi

exit "$failed"
