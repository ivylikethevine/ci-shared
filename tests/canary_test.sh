#!/usr/bin/env bash
# scripts/canary.sh: each target with a canary is cloned at its sync branch,
# files/ is written in, and its command runs there; a failing command, a
# clone that fails and a rendering that fails each fail the run. The remotes
# are bare repositories under $T/remote.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# remote <name> - owner/<name> on the fake remote, its main holding check.sh,
# which passes when the shared file reads `good`
remote() {
  t_checkout "src-$1" 'check.sh=grep -qx good shared.txt' 'shared.txt=old'
  mkdir -p "$T/remote/owner"
  t_git "$T" clone -q --bare "$T/src-$1" "$T/remote/owner/$1.git"
}

# canary [NAME...] - the script against the fake remote
canary() {
  t_run env CI_CANARY_REMOTE="file://$T/remote" "$SCRIPTS/canary.sh" "$@"
}

fixture() {
  echo "$1" | t_shared shared.txt
  remote a
  t_target a main shared.txt
  echo 'canary = ["sh", "check.sh"]' | t_toml a
  # no canary, and no clone for sync_local.sh to write into
  t_target b main shared.txt
}

test_a_canary_passes_on_the_files_written_in() {
  fixture good
  canary
  t_rc 0
  t_out 'b: no canary, skipped' 'a: shared.txt updated' 'a: canary passed'
  t_no_out 'no checkout at' '::group::'
}

test_a_failing_canary_fails_the_run_in_a_group() {
  fixture bad
  t_run env CI_CANARY_REMOTE="file://$T/remote" GITHUB_ACTIONS=true "$SCRIPTS/canary.sh" a
  t_rc 1
  t_out '::group::canary a: sh check.sh' '::endgroup::' \
    "::error title=canary a::sh check.sh exited 1 on a's main with files/ written in"
  t_no_out 'b: no canary' 'a: canary passed'
}

test_a_clone_that_fails_fails_its_target_alone() {
  fixture good
  t_target c dev shared.txt
  echo 'canary = ["true"]' | t_toml c
  remote c
  canary
  t_rc 1
  t_out '::error title=canary c::could not clone owner/c at dev' 'a: canary passed'
}

test_no_canary_runs_nothing() {
  fixture good
  canary b
  t_rc 0
  t_out 'b: no canary, skipped'
  t_no_out 'updated'
}

test_an_unknown_target_fails() {
  fixture good
  canary nosuch
  t_rc 1
  t_out 'repos/ has no target nosuch'
}

test_a_rendering_that_fails_fails_the_run() {
  fixture good
  printf '# shared:else\n' | t_shared broken.txt
  t_target a main shared.txt broken.txt
  echo 'canary = ["true"]' | t_toml a
  canary a
  [ "$T_RC" != 0 ] || t_fail "exit 0"
  t_out 'shared:else outside a block'
  t_no_out 'canary passed'
}

t_main
