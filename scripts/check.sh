#!/usr/bin/env bash
# Runs the checks this repository ships over the repository itself, files/
# included, with the shared configs: that every tools.txt tool checks.yml
# installs is its pinned version here, shellcheck and shfmt (.shellcheckrc,
# .editorconfig), constricter over the Python (pyproject.toml), actionlint, lint_workflows.sh, zizmor (.github/zizmor.yml),
# prettier and markdownlint (.prettierrc.yaml, .markdownlint.yaml), lychee
# offline over the tracked Markdown (lychee.toml), typos,
# gitleaks over the history, reuse lint (REUSE.toml, LICENSES/), pip-audit over
# requirements-dev.txt and npm audit over .github/package-lock.json (less the advisories
# files/.github/osv-scanner.toml accepts), then each template as every target
# receives it:
# actionlint and lint_workflows.sh for a workflow, markdownlint for Markdown,
# prettier for what it has a parser for, and no `__key__` left that a target
# sets. USAGE.md and the copies scripts/own_files.sh writes must be
# current, and no shared file be ignored by files/.gitignore. CI's checks
# workflow runs the same script.
#
#   scripts/check.sh
#
# Needs the tools.txt pins and requirements-dev.txt's tools on PATH, and
# `npm ci --prefix .github` once. A
# missing tool fails its check rather than skipping it. Exits with the number
# of checks that failed.
set -uo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$CI_SHARED_DIR" || exit 1
ci_tmpdir

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

# The tools.txt tools checks.yml installs must be their pins on PATH too: a
# local run on another version can pass where CI fails, or the reverse.
CI_TOOLS_TXT="${CI_TOOLS_TXT:-$CI_SHARED_DIR/files/.github/actions/setup-tool/tools.txt}"
# shellcheck source=../files/.github/actions/setup-tool/lib.sh
source "$CI_SCRIPTS_DIR/../files/.github/actions/setup-tool/lib.sh"
# shellcheck disable=SC2329 # run calls it by name
pins() {
  local ok=0 tool row pin verify out tools=()
  read -ra tools <<<"$(sed -n 's/^ *tools: //p' .github/workflows/checks.yml)"
  for tool in "${tools[@]}"; do
    row="$(_ci_tool_row "$tool")" || {
      ok=1
      continue
    }
    IFS='|' read -r _ pin _ _ verify _ <<<"$row"
    # shellcheck disable=SC2086 # the verify column is flags, split on purpose
    out="$("$tool" $verify 2>&1)"
    grep -qE "(^|[^0-9.])v?${pin//./\\.}([^0-9.]|\$)" <<<"$out" || {
      echo "$tool is not the pinned $pin: $(grep -m1 . <<<"$out")"
      ok=1
    }
  done
  return "$ok"
}
run pins pins
# zizmor reads GH_TOKEN itself for its online audits, and refuses an empty
# one, so an empty token is unset rather than left for it to find
offline=()
[ -n "${GH_TOKEN:-}" ] || {
  unset GH_TOKEN
  offline=(--offline)
}

# A template workflow's blocks can hold a value a target chooses (an egress
# policy), so lint_workflows.sh reads it rendered below, not raw
raw_lint_workflows=()
for f in "${workflows[@]}"; do
  case $f in files/*) ! ci_is_template "${f#files/}" || continue ;; esac
  raw_lint_workflows+=("$f")
done
run shellcheck shellcheck -x "${scripts[@]}"
run shfmt shfmt -d "${scripts[@]}"
run constricter constricter scripts tests
run actionlint actionlint "${workflows[@]}"
run lint-workflows .github/scripts/lint_workflows.sh "${raw_lint_workflows[@]}" files/.github/actions/*/action.yml
run zizmor zizmor --config .github/zizmor.yml ${offline[@]+"${offline[@]}"} .github/workflows files/.github
# A Markdown template's markers break the lists around them, and a JSON
# template's are not JSON, so the raw copies are formatted rendered below
# instead. .claude/ and local/ are untracked (agent state, which a session may
# mount as unreadable devices, and this machine's output), as lychee.toml
# excludes them too.
raw_prettier=(.) raw_markdownlint=('**/*.md' '#**/node_modules' '#.claude' '#local')
while IFS= read -r f; do
  ci_is_template "${f#files/}" || continue
  raw_prettier+=("!$f")
  case $f in *.md) raw_markdownlint+=("#$f") ;; esac
done < <(find files \( -name '*.md' -o -name '*.json' \) -type f | LC_ALL=C sort)
run prettier "$bin/prettier" --check "${raw_prettier[@]}"
run markdownlint "$bin/markdownlint-cli2" "${raw_markdownlint[@]}"
# lychee offline, as each target's CI runs it: a relative link or an anchor
# that no longer resolves. link-check.yml sweeps the external links weekly.
# shellcheck disable=SC2329 # run calls it by name
links() {
  git ls-files -z '*.md' | xargs -0 -r lychee --config lychee.toml --offline --include-fragments --no-progress
}
run lychee links
run typos typos
run gitleaks gitleaks git --redact --no-banner .
run reuse reuse --no-multiprocessing lint

# The locks, as advisories.yml reads them: npm audit exits non-zero on a
# finding and on a failure alike, and its JSON carries a count only when the
# audit ran. An advisory is its GHSA id, the last segment of the url npm
# reports it under.
# shellcheck disable=SC2329 # run calls it by name
audit() {
  local ok=0 report open
  pip-audit --strict --require-hashes --disable-pip -r requirements-dev.txt || ok=1
  report="$CI_TMP/npm-audit.json"
  npm audit --prefix .github --json >"$report" 2>&1 || true
  if ! jq -e '.metadata.vulnerabilities.total' "$report" >/dev/null 2>&1; then
    cat "$report"
    echo "npm audit did not run"
    ok=1
  else
    open="$(jq -r '[.vulnerabilities[]?.via[] | objects | .url | sub(".*/"; "")] | unique[]' "$report" |
      grep -vxFf <(sed -n 's/^id = "\(GHSA[-0-9a-z]*\)"$/\1/p' files/.github/osv-scanner.toml) || true)"
    [ -z "$open" ] || {
      echo "npm audit reports advisories files/.github/osv-scanner.toml does not accept:"
      echo "$open"
      ok=1
    }
  fi
  return "$ok"
}
run audit audit
run usage "$CI_SCRIPTS_DIR/usage.sh" --check
run own-files "$CI_SCRIPTS_DIR/own_files.sh" --check

# Each template rendered for every target that receives it, so a placeholder or
# block that breaks only one repository's copy still fails here.
run config ci_load
rows="$(ci_rows)"

# Every target has a mint step in sync.yml and a TOKEN_<NAME> line taking its
# token: one missing otherwise only shows when a run skips the target.
# shellcheck disable=SC2329 # run calls it by name
mint() {
  local ok=0 name secret
  while read -r name secret; do
    if ! grep -qE "^ +repositories: $name\$" .github/workflows/sync.yml ||
      ! grep -qF "${secret#SYNC_}: \${{ steps.app-$name.outputs.token }}" .github/workflows/sync.yml; then
      echo "$name has no mint step or ${secret#SYNC_} line in .github/workflows/sync.yml"
      ok=1
    fi
  done < <(ci_configs | jq -r '.[] | "\(.name) \(.token_secret)"')
  return "$ok"
}
run mint mint

# files/.gitignore is the template with every target's block active, so git
# applies a target's blanket rule (*.toml, *.txt) to files/ here, and a new
# shared file it matches never reaches a commit unless the template negates
# it. Tracked files are past the rules, so this catches the one not yet added.
# shellcheck disable=SC2329 # run calls it by name
ignored() {
  local found=0 path
  while read -r path; do
    git check-ignore -q -- "files/$path" || continue
    echo "files/$path is ignored by files/.gitignore: negate the rule in the template"
    found=1
  done < <(cut -d' ' -f2 <<<"$rows" | LC_ALL=C sort -u)
  [ "$found" = 0 ]
}
run ignored ignored
rendered="$CI_TMP/render"
templates=() workflows_rendered=() md_rendered=()
declare -A keys=()
# shellcheck disable=SC2086 # $vars is key=value words, split on purpose
while read -r name path vars; do
  # a template's row carries at least repo=<name>
  [ -n "$vars" ] || continue
  mkdir -p "$rendered/$name/$(dirname "$path")"
  ci_render "$path" $vars >"$rendered/$name/$path"
  templates+=("$rendered/$name/$path")
  case "$path" in
  .github/workflows/*) workflows_rendered+=("$rendered/$name/$path") ;;
  *.md) md_rendered+=("$rendered/$name/$path") ;;
  esac
  for kv in $vars; do keys[$path]="${keys[$path]:-} ${kv%%=*}"; done
done <<<"$rows"

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
  # named: a rendering sits outside this tree, where actionlint would not find
  # the runner labels it is told of
  run actionlint-rendered actionlint -config-file .github/actionlint.yaml "${workflows_rendered[@]}"
  run lint-workflows-rendered .github/scripts/lint_workflows.sh "${workflows_rendered[@]}"
fi
if [ ${#md_rendered[@]} -gt 0 ]; then
  run markdownlint-rendered "$bin/markdownlint-cli2" --config .markdownlint.yaml "${md_rendered[@]}"
fi

exit "$failed"
