#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs scripts/check_protection.sh against a fake `gh` in a scratch copy of the
# repository, once per scenario, and checks it passes only the fully protected
# one: every API error, odd response, unknown bypass level, missing branch,
# missing token and bad repos/ config must fail it.
#
#   scratch/test_check_protection.sh
#
# Needs bash, jq, Python 3.11+ and mktemp; touches nothing outside the
# temporary copy.
set -euo pipefail

src="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
root="$(mktemp -d "${TMPDIR:-/tmp}/check-protection.XXXXXX")"
cleanup() {
  case $root in */check-protection.??????) rm -r -- "$root" ;; esac
}
trap cleanup EXIT

mkdir -p "$root/scripts" "$root/bin" "$root/files"
cp "$src/scripts/lib.sh" "$src/scripts/config.py" "$src/scripts/check_protection.sh" "$root/scripts/"

# The fake answers the three endpoints the check reads. Ruleset 1 holds main,
# ruleset 2 holds dev; SCENARIO bends one answer at a time.
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] || exit 2
ep=$2
s=${SCENARIO:-pass}
fail() { echo '{"message":"Not Found","status":"404"}'; exit 1; }
ruleset() {
  local id=$1 bypass=${2-never} enf=${3-active}
  [ "$s" = ruleset-error ] && fail
  [ "$s" = ruleset-id ] && id=99
  jq -n --argjson id "$id" --arg b "$bypass" --arg e "$enf" --arg s "$s" \
    '{id: $id, name: "r\($id)", enforcement: $e}
     + (if $s == "bypass-missing" then {} else {current_user_can_bypass: $b} end)'
}
case $ep in
  */git/matching-refs/heads/main) echo '[{"ref":"refs/heads/main"}]' ;;
  */git/matching-refs/heads/dev)
    [ "$s" = dev-missing ] && echo '[{"ref":"refs/heads/devel"}]' && exit 0
    echo '[{"ref":"refs/heads/dev"}]' ;;
  */rules/branches/main*)
    [ "$s" = rules-error ] && fail
    [ "$s" = rules-object ] && echo '{"type":"pull_request","ruleset_id":1}' && exit 0
    [ "$s" = rules-garbage ] && echo 'not json' && exit 0
    echo '[{"type":"pull_request","ruleset_id":1},{"type":"non_fast_forward","ruleset_id":1},{"type":"deletion","ruleset_id":1}]' ;;
  */rules/branches/dev*)
    echo '[{"type":"required_signatures","ruleset_id":2},{"type":"non_fast_forward","ruleset_id":2},{"type":"deletion","ruleset_id":2}]' ;;
  */rulesets/1)
    case $s in
      bypass-always) ruleset 1 always ;;
      bypass-unknown) ruleset 1 sometimes ;;
      evaluate) ruleset 1 never evaluate ;;
      *) ruleset 1 ;;
    esac ;;
  */rulesets/2) ruleset 2 pull_requests_only ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$root/bin/gh"

pass=0 fail=0
# expect <0|1> <scenario> [GH_TOKEN] [name=toml...] - with no configs given,
# repos/repo.toml targets owner/repo on dev
expect() {
  local want=$1 scenario=$2 token=${3-fake} got=0 c
  shift $(($# < 3 ? $# : 3))
  [ $# -gt 0 ] || set -- 'repo=repository = "owner/repo"
sync_branch = "dev"'
  case $root/repos in */check-protection.??????/repos) [ ! -d "$root/repos" ] || rm -r -- "$root/repos" ;; esac
  mkdir "$root/repos"
  for c in "$@"; do
    [ -z "$c" ] || printf '%s\n' "${c#*=}" >"$root/repos/${c%%=*}.toml"
  done
  PATH="$root/bin:$PATH" SCENARIO=$scenario GH_TOKEN=$token \
    "$root/scripts/check_protection.sh" >"$root/out" 2>&1 || got=$?
  [ "$got" = 0 ] || got=1
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $scenario: wanted exit $want, got $got"
    sed 's/^/  /' "$root/out"
  fi
}

ok='repository = "owner/repo"'
expect 0 pass
expect 0 main-base fake "repo=$ok
sync_branch = \"main\""
for s in bypass-always bypass-unknown bypass-missing evaluate rules-error \
  rules-object rules-garbage ruleset-error ruleset-id dev-missing; do
  expect 1 "$s"
done
expect 1 no-token ""
expect 1 no-configs fake ""
expect 1 bad-slug fake 'repo=repository = "not-a-slug"
sync_branch = "dev"'
expect 1 name-mismatch fake 'other=repository = "owner/repo"
sync_branch = "dev"'
expect 1 unknown-key fake "repo=$ok
sync_branch = \"dev\"
extra = 1"
expect 1 other-base fake "repo=$ok
sync_branch = \"release\""
expect 1 no-base fake "repo=$ok"
expect 1 bad-toml fake 'repo=repository = "owner/repo'
expect 1 missing-file fake "repo=$ok
sync_branch = \"dev\"
files = [\"nope\"]"
expect 1 one-bad-of-two fake "repo=$ok
sync_branch = \"dev\"" 'repo2=repository = "owner/repo2"
sync_branch = "release"'

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
