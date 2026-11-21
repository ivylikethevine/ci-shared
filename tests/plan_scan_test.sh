#!/usr/bin/env bash
# files/.claude/plan-scan on a fixture repo: each category is found, allowed
# values and a plan-allow line are not, the repo's own allow list excuses names
# and no pattern, the hook blocks a plan, a rule, a rule draft and a file the
# repo's .claude/plan-scan.paths lists and passes everything else, a full scan
# covers the same set, --promote moves only a clean draft, a project copy the
# project's settings run takes over from an installed one and checks its
# recorded sha256, gitleaks' findings are
# redacted, and the scan runs under bash 3.2 in a container. Needs rg (with
# PCRE2), jq and git; gitleaks and the container check run where available.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCAN="$REPO_DIR/files/.claude/plan-scan"

# fixture - $repo, a git repo under a root of folders, the data dir's lists, and
# $plan, a plan holding one finding of each kind; exports PLAN_SCAN_DIR
fixture() {
  repo="$T/roots/grp/this-repo"
  mkdir -p "$repo/docs/plans" "$repo/.claude" "$T/roots/grp/other-repo" \
    "$T/roots/grp/client/client-api/.git" "$T/roots/personal" "$T/roots/grp/docs" "$T/data"
  t_git "$repo" init -q
  printf '%s\n' '# machines' frobnicator >"$T/data/denylist"
  printf '%s\n' "$T/roots" >"$T/data/roots"
  printf '%s\n' personal docs git@github.com >"$T/data/allow"
  export PLAN_SCAN_DIR="$T/data"
  plan="$repo/docs/plans/fixture.md"
  cat >"$plan" <<'EOF'
1. Edit /home/someone/file.ts and ~/notes.md, then $HOME/x.
2. Ask dev@company.io, not test@example.com; push to git@github.com.
3. Reach 192.168.1.5 or fe80::1ff:fe23:4567:890a; not 127.0.0.1 or 10.0.2.2.
4. The MAC is aa:bb:cc:dd:ee:ff and the box is office-box.local; settings.local.json is a file.
5. Simulator 23EAEB58-BBB1-48F3-A878-4691D3CB9AE8; seed 00000000-0000-4000-8000-000000000001.
6. Ask the frobnicator about other-repo; this-repo and grp name themselves.
7. Brew lives at /opt/homebrew/bin/bash; state in .claude/projects/x/y.jsonl.
8. GH_TOKEN=abcdef123456
<!-- plan-allow -->
9. Deliberate: /home/someone/allowed.
10. The personal and docs folders and mobile/src/App.tsx are fine.
EOF
  # the list words themselves are never written in this repository
  printf '11. Hosts on the %s and the denied ones.\n' "white""list" >>"$plan"
  clean="$repo/docs/plans/clean.md"
  printf '%s\n' '# Clean' 'Edit mobile/src/App.tsx on the Mac.' >"$clean"
}

# hook FILE [PROJECT] - the installed hook's exit status for a write of FILE;
# the input is a here-string, since a hook that defers exits without reading it
hook() {
  local input
  input="$(jq -n --arg v "$1" '{tool_name: "Write", tool_input: {file_path: $v}}')"
  CLAUDE_PROJECT_DIR=${2-} bash "$SCAN" --hook <<<"$input" >/dev/null 2>&1 && echo 0 || echo $?
}

# phook FILE - the project copy's hook, its output in $T/out and status in T_RC
phook() {
  local input
  input="$(jq -n --arg v "$1" '{tool_name: "Write", tool_input: {file_path: $v}}')"
  T_RC=0
  CLAUDE_PROJECT_DIR=$repo bash "$repo/.claude/plan-scan" --hook <<<"$input" >"$T/out" 2>&1 || T_RC=$?
}

test_reports_each_category() {
  fixture
  t_run bash "$SCAN" "$plan"
  t_rc 1
  t_out "fixture.md:1: home path: /home/someone/file.ts" \
    "fixture.md:1: home-relative path: ~/notes.md" \
    "fixture.md:1: home variable: \$HOME" \
    "fixture.md:2: email: dev@company.io" \
    "fixture.md:3: IPv4 address: 192.168.1.5" \
    "fixture.md:3: IPv6 address: fe80::1ff:fe23:4567:890a" \
    "fixture.md:4: MAC address: aa:bb:cc:dd:ee:ff" \
    "fixture.md:4: local hostname: office-box.local" \
    "fixture.md:5: UUID (device, simulator or session id): 23EAEB58-BBB1-48F3-A878-4691D3CB9AE8" \
    "fixture.md:6: denylisted name: frobnicator" \
    "fixture.md:6: folder name: other-repo" \
    "fixture.md:7: tool prefix path: /opt/homebrew/bin/bash" \
    "fixture.md:7: Claude Code state path: .claude/projects/x/y.jsonl" \
    "fixture.md:8: secret-named value: GH_TOKEN=abcdef123456" \
    "fixture.md:12: wording (allowed, denied): white""list"
}

test_passes_what_is_allowed() {
  fixture
  t_run bash "$SCAN" "$plan"
  t_no_out example.com settings.local.json 127.0.0.1 10.0.2.2 00000000-0000 \
    ": this-repo" ": grp" fixture.md:10: ": personal" ": docs" git@github.com \
    App.tsx y.jsonl.
  t_run bash "$SCAN" "$clean"
  t_rc 0
}

test_the_repo_allow_list_excuses_names_only() {
  fixture
  printf '%s\n' '# names' frobnicator other-repo dev@company.io >"$repo/.claude/plan-scan.allow"
  t_run bash "$SCAN" "$plan"
  t_no_out ": frobnicator" ": other-repo"
  t_out "fixture.md:2: email: dev@company.io"
}

test_the_hook_covers_plans_rules_and_listed_files() {
  fixture
  mkdir -p "$repo/.claude/rules" "$repo/local/rules" "$repo/docs/guide"
  cp "$plan" "$repo/notes.md"
  cp "$plan" "$repo/.claude/rules/rule.md"
  cp "$plan" "$repo/local/rules/draft.md"
  cp "$plan" "$repo/README.md"
  cp "$plan" "$repo/docs/guide/setup.md"
  t_eq "$(hook "$plan")" 2 "a dirty plan"
  t_eq "$(hook "$clean")" 0 "a clean plan"
  t_eq "$(hook "$repo/notes.md")" 0 "a file outside docs/plans"
  t_eq "$(hook "$repo/.claude/rules/rule.md")" 2 "a dirty rule"
  t_eq "$(hook "$repo/local/rules/draft.md")" 2 "a dirty rule draft"
  t_eq "$(hook "$repo/README.md")" 0 "an unlisted README"
  t_eq "$(hook "$T/gone.md")" 0 "a file that is gone"
  printf '%s\n' '# committed notes' README.md 'docs/*.md' >"$repo/.claude/plan-scan.paths"
  t_eq "$(hook "$repo/README.md")" 2 "a listed README"
  t_eq "$(hook "$repo/docs/guide/setup.md")" 2 "a listed glob across folders"
  t_eq "$(hook "$repo/notes.md")" 0 "an unlisted file beside a list"
  T_RC=0
  (cd "$repo" && bash "$SCAN") >"$T/out" 2>/dev/null || T_RC=$?
  t_rc 1
  t_out "docs/plans/fixture.md:1: home path" ".claude/rules/rule.md:1: home path" \
    "local/rules/draft.md:1: home path" "README.md:1: home path" "docs/guide/setup.md:1: home path"
  t_no_out "clean.md:" "notes.md:"
}

test_promote_moves_a_clean_draft_only() {
  fixture
  mkdir -p "$repo/local/rules"
  cp "$clean" "$repo/local/rules/good.md"
  cp "$plan" "$repo/local/rules/draft.md"
  T_RC=0
  (cd "$repo" && bash "$SCAN" --promote good) >"$T/out" 2>&1 || T_RC=$?
  t_rc 0
  t_out "moved good.md"
  [ -f "$repo/.claude/rules/good.md" ] && [ ! -e "$repo/local/rules/good.md" ] || t_fail "good.md did not move"
  T_RC=0
  (cd "$repo" && bash "$SCAN" --promote draft.md) >"$T/out" 2>&1 || T_RC=$?
  t_rc 1
  t_out "draft.md:1: home path" "draft.md failed the scan"
  [ -f "$repo/local/rules/draft.md" ] || t_fail "the refused draft moved"
  cp "$clean" "$repo/local/rules/good.md"
  T_RC=0
  (cd "$repo" && bash "$SCAN" --promote good) >"$T/out" 2>&1 || T_RC=$?
  t_rc 2
  T_RC=0
  (cd "$repo" && bash "$SCAN" --promote nothing) >"$T/out" 2>&1 || T_RC=$?
  t_rc 2
}

test_a_project_copy_its_settings_run_takes_over() {
  fixture
  cp "$SCAN" "$repo/.claude/plan-scan"
  sha256sum "$repo/.claude/plan-scan" | awk '{ print $1 "  plan-scan" }' >"$repo/.claude/plan-scan.sha256"
  echo '{"permissions": {}}' >"$repo/.claude/settings.json"
  t_eq "$(hook "$plan" "$repo")" 2 "a copy the project only carries: the installed one scans"
  # shellcheck disable=SC2016 # the settings' literal command
  printf '{"hooks": {"PostToolUse": [{"hooks": [{"command": "bash \\"$CLAUDE_PROJECT_DIR\\"/.claude/plan-scan --hook"}]}]}}\n' \
    >"$repo/.claude/settings.json"
  t_eq "$(hook "$plan" "$repo")" 0 "a copy the project's settings run: the installed one defers"
  rm "$repo/.claude/settings.json"
  echo '{"hooks": {"PostToolUse": [{"hooks": [{"command": ".claude/plan-scan --hook"}]}]}}' \
    >"$repo/.claude/settings.local.json"
  t_eq "$(hook "$plan" "$repo")" 0 "a copy the local settings run: the installed one defers"
  phook "$plan"
  t_rc 2
  t_out "fixture.md:1: home path"
  phook "$clean"
  t_rc 0
  printf '%s  plan-scan\n' 0123abcd >"$repo/.claude/plan-scan.sha256"
  phook "$clean"
  t_rc 2
  t_out drifted
  phook "$repo/README.md"
  t_rc 0
}

test_gitleaks_findings_are_redacted() {
  command -v gitleaks >/dev/null || {
    echo "  skip: gitleaks not installed"
    return 0
  }
  fixture
  printf 'token: ghp_%s\n' "$(printf 'a1B2c3D4e5%.0s' 1 2 3 4)" | cut -c1-47 >"$T/secret.md"
  t_run bash "$SCAN" "$T/secret.md"
  t_rc 1
  t_out "secret.md:1: secret (gitleaks): github-pat"
  t_no_out ghp_
}

# under CI the image pull is skipped: a network fetch per run for one check
test_runs_under_bash_3_2() {
  local engine
  engine="$(command -v podman || command -v docker)" || engine=""
  if [ -n "${CI:-}" ] || [ -z "$engine" ] || ! "$engine" info >/dev/null 2>&1; then
    echo "  skip: bash 3.2 needs podman or docker outside CI"
    return 0
  fi
  fixture
  # shellcheck disable=SC2016 # expanded by the container's shell
  t_run "$engine" run --rm --network=host -v "$SCAN:/s/plan-scan:ro,Z" -v "$plan:/s/plan.md:ro,Z" \
    docker.io/library/bash:3.2 sh -c '
      apk add -q --no-cache ripgrep jq git >/dev/null || exit 3
      PLAN_SCAN_DIR=/nonexistent bash /s/plan-scan /s/plan.md 2>/dev/null
      echo "exit=$? bash=$(bash -c "echo \$BASH_VERSION")"'
  t_out "exit=1 bash=3.2" "plan.md:1: home path: /home/someone/file.ts"
}

t_main
