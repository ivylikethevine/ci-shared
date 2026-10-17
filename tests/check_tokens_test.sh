#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check_tokens.sh against a fake GitHub: it prints each token's expiry,
# and fails a token that is unset, cannot read its target, has no expiry, sent
# one it cannot read, or expires within two weeks.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The token decides the answer: days:<n> expires in n days and an hour, none
# has no expiry, garbage sends one date cannot read, denied gets a 401, down
# gets no response at all.
fake_github() {
  t_fake_gh <<'EOF'
[ "$include" = 1 ] || fail "no --include"
status='HTTP/2.0 200 OK'
case $GH_TOKEN in
days:*)
  exp="$(date -u -d "@$(($(date +%s) + ${GH_TOKEN#days:} * 86400 + 3600))" '+%Y-%m-%d %H:%M:%S UTC')"
  header="Github-Authentication-Token-Expiration: $exp"
  ;;
none) header='' ;;
garbage) header='Github-Authentication-Token-Expiration: soon' ;;
denied)
  printf 'HTTP/2.0 401 Unauthorized\r\n\r\n{}\n'
  fail "HTTP 401"
  ;;
*) fail "no response" ;;
esac
printf '%s\r\n' "$status" ${header:+"$header"}
printf '\r\n{"full_name":"%s"}\n' "${ep#repos/}"
EOF
}

test_prints_each_expiry() {
  fake_github
  t_target a dev
  t_target b-c dev
  t_run env SYNC_TOKEN_A=days:30 SYNC_TOKEN_B_C=days:14 "$SCRIPTS/check_tokens.sh"
  t_rc 0
  t_out "a: SYNC_TOKEN_A expires 2" " UTC, in 30 days" \
    "b-c: SYNC_TOKEN_B_C expires" ", in 14 days"
  t_logged '^GET repos/owner/a$'
  t_logged '^GET repos/owner/b-c$'
}

test_fails_each_bad_token() {
  fake_github
  t_target a dev
  t_target b dev
  t_target c dev
  t_target d dev
  t_target e dev
  t_target f dev
  t_run env GH_TOKEN=days:90 SYNC_TOKEN_B=days:13 SYNC_TOKEN_C=none SYNC_TOKEN_D=garbage \
    SYNC_TOKEN_E=denied SYNC_TOKEN_F=down "$SCRIPTS/check_tokens.sh"
  t_rc 6
  t_out "::error title=token a::SYNC_TOKEN_A is not set" \
    "::error title=token b::SYNC_TOKEN_B expires" ", in 13 days: renew it" \
    "::error title=token c::SYNC_TOKEN_C has no expiry date" \
    "::error title=token d::SYNC_TOKEN_D has an expiry GitHub sent as 'soon'" \
    "::error title=token e::SYNC_TOKEN_E cannot read owner/e (HTTP/2.0 401 Unauthorized)"
  t_in -x "$T/out" "::error title=token f::SYNC_TOKEN_F cannot read owner/f"
  t_not_logged 'owner/a'
}

test_checks_the_named_targets_alone() {
  fake_github
  t_target a dev
  t_target b dev
  t_run env SYNC_TOKEN_B=days:30 "$SCRIPTS/check_tokens.sh" b
  t_rc 0
  t_out "b: SYNC_TOKEN_B expires"
  t_no_out "a:"
  t_run env SYNC_TOKEN_B=days:30 "$SCRIPTS/check_tokens.sh" b nope
  t_rc 1
  t_out "repos/ has no target nope"
  t_no_out "b:"
}

t_main
