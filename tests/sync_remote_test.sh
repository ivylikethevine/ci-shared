#!/usr/bin/env bash
# scripts/sync_remote.sh against a fake GitHub: one commit and one pull request
# per target that differs, each written with its own token, nothing written on
# a dry run, and nothing to a target that fails its protection check or a
# call.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A fake gh answering what check_protection.sh and sync_remote.sh read and
# write, and the signing key and identity it verifies. $T/listing.json is the
# base branch's tree; SCENARIO bends one answer: unprotected, unprotected-a
# (owner/a alone), truncated, bad-blob, tree-error, bad-commit, unverified,
# branch-exists, pr-open. $T/tokens.log gets "token METHOD endpoint" per call.
fake_github() {
  echo '[]' >"$T/listing.json"
  ssh-keygen -q -t ed25519 -N '' -C sync -f "$T/key"
  SYNC_SIGNING_KEY="$(cat "$T/key")"
  export SYNC_SIGNING_KEY SYNC_COMMITTER_NAME=Sync SYNC_COMMITTER_EMAIL=sync@example.invalid
  t_fake_gh <<'EOF'
s=${SCENARIO:-}
echo "${GH_TOKEN:-} $method $ep" >>"$T/tokens.log"
case "$method $ep" in
"GET "*/git/matching-refs/heads/*) reply "[{\"ref\":\"refs/heads/${ep##*/}\"}]" ;;
"GET "*/rules/branches/*)
  case "$s $ep" in
  "unprotected "* | "unprotected-a repos/owner/a/"*) reply '[]' ;;
  *) reply '[{"type":"pull_request","ruleset_id":1},{"type":"non_fast_forward","ruleset_id":1},{"type":"deletion","ruleset_id":1}]' ;;
  esac
  ;;
"GET "*/rulesets/1) reply '{"id":1,"name":"r","enforcement":"active","current_user_can_bypass":"never"}' ;;
"GET "*/git/ref/heads/ci-sync) [ "$s" = branch-exists ] && reply '{}' || fail "HTTP 404" ;;
"GET "*/git/ref/heads/*) reply '{"object":{"sha":"head1"}}' ;;
"GET "*/git/commits/head1) reply '{"tree":{"sha":"tree1"}}' ;;
"GET "*/git/trees/tree1*)
  jq --argjson t "$(cat "$T/listing.json")" \
    '{truncated: ($s == "truncated"), tree: $t}' --arg s "$s" -n | reply "$(cat)"
  ;;
"POST "*/git/blobs)
  sha="$(jq -r .content <<<"$input" | base64 -d | git hash-object --stdin)"
  [ "$s" != bad-blob ] || sha=0000000000000000000000000000000000000000
  reply "{\"sha\":\"$sha\"}"
  ;;
"POST "*/git/trees)
  [ "$s" != tree-error ] || fail
  printf '%s\n' "$input" >"$T/tree.json"
  reply '{"sha":"tree2"}'
  ;;
"POST "*/git/commits)
  printf '%s\n' "$input" >"$T/commit.json"
  # the object GitHub stores: the signature as a gpgsig header
  sha="$(jq -j '
    def who: "\(.name) <\(.email)> \(.date | fromdate) +0000";
    "tree \(.tree)\nparent \(.parents[0])\nauthor \(.author | who)\ncommitter \(.committer | who)\n"
    + "gpgsig \(.signature | gsub("\n"; "\n "))\n\n\(.message)"' <<<"$input" |
    git hash-object -t commit --stdin)"
  [ "$s" != bad-commit ] || sha=1111111111111111111111111111111111111111
  echo "$sha" >"$T/commit.sha"
  [ "$s" = unverified ] && v='false,"reason":"no_user"' || v='true,"reason":"valid"'
  reply "{\"sha\":\"$sha\",\"verification\":{\"verified\":$v}}"
  ;;
"PATCH "*/git/refs/heads/ci-sync | "POST "*/git/refs) printf '%s\n' "${fields[@]}" >"$T/ref.txt" ;;
"GET "*/pulls\?*)
  case $s in
  pr-open | pr-draft) reply "[{\"number\":7,\"node_id\":\"PR_7\",\"draft\":$([ "$s" = pr-draft ] && echo true || echo false),\"html_url\":\"https://example.invalid/pull/7\"}]" ;;
  *) reply '[]' ;;
  esac
  ;;
"POST graphql") printf '%s\n' "${fields[@]}" >"$T/graphql.txt" ;;
"PATCH "*/pulls/7) printf '%s\n' "${fields[@]}" >"$T/pr.txt" ;;
"POST "*/pulls)
  printf '%s\n' "${fields[@]}" >"$T/pr.txt"
  reply '{"number":8,"html_url":"https://example.invalid/pull/8"}'
  ;;
*) fail "unexpected $method $ep" ;;
esac
EOF
}

# targets a (two files, one in line already) and b (one file)
fixture() {
  echo same | t_shared same.txt
  printf '#!/bin/sh\n' | t_shared new.sh x
  t_target a dev same.txt new.sh
  t_target b main same.txt
  jq -n --arg s "$(git hash-object "$T/tree/files/same.txt")" \
    '[{path: "same.txt", mode: "100644", type: "blob", sha: $s}]' >"$T/listing.json"
}

test_opens_a_pull_request_for_what_differs() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SOURCE_SHA=abc123 "$SCRIPTS/sync_remote.sh" a
  t_rc 0
  t_out "owner/a main: protected" "a: new.sh differs" "a: opened pull request #8"
  t_no_out "same.txt differs" "b:"
  t_eq "$(jq -c '.tree' "$T/tree.json")" \
    "[{\"path\":\"new.sh\",\"mode\":\"100755\",\"type\":\"blob\",\"sha\":\"$(git hash-object "$T/tree/files/new.sh")\"}]" "the new tree"
  t_eq "$(jq -r .base_tree "$T/tree.json")" tree1 "the base tree"
  t_eq "$(jq -c '[.message, .tree, .parents]' "$T/commit.json")" \
    '["ci: sync shared CI files\n\nSource: abc123","tree2",["head1"]]' "the commit"
  t_eq "$(jq -c '[.author, .committer] | map([.name, .email]) | unique' "$T/commit.json")" \
    '[["Sync","sync@example.invalid"]]' "the commit's author and committer"
  # the signature covers the commit object as it is without one
  jq -j '
    def who: "\(.name) <\(.email)> \(.date | fromdate) +0000";
    "tree \(.tree)\nparent \(.parents[0])\nauthor \(.author | who)\ncommitter \(.committer | who)\n\n\(.message)"' \
    "$T/commit.json" >"$T/payload"
  jq -r .signature "$T/commit.json" >"$T/sig"
  printf 'sync@example.invalid namespaces="git" %s\n' "$(cat "$T/key.pub")" >"$T/allowed"
  ssh-keygen -Y verify -f "$T/allowed" -I sync@example.invalid -n git -s "$T/sig" <"$T/payload" >/dev/null 2>&1 ||
    t_fail "the signature does not verify against the unsigned commit"
  t_logged '^POST repos/owner/a/git/refs$'
  t_file "$T/ref.txt" "$(printf 'ref=refs/heads/ci-sync\nsha=%s' "$(cat "$T/commit.sha")")"
  # shellcheck disable=SC2016 # literal text
  t_in "$T/pr.txt" head=ci-sync base=dev draft=true '- `new.sh`'
}

test_moves_the_branch_and_updates_an_open_pull_request() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=branch-exists "$SCRIPTS/sync_remote.sh" b
  t_rc 0
  t_out "b: in line with files/"
  t_run env GH_TOKEN=t SCENARIO=pr-open "$SCRIPTS/sync_remote.sh" a
  t_rc 0
  t_out "a: updated pull request #7"
  t_logged '^PATCH repos/owner/a/pulls/7$'
  # marked ready: back to draft before the branch moves
  t_in "$T/graphql.txt" id=PR_7 convertPullRequestToDraft
  t_eq "$(grep -n -E '^(POST graphql|POST repos/owner/a/git/refs)$' "$GH_LOG" | cut -d' ' -f2)" \
    "graphql"$'\n'"repos/owner/a/git/refs" "draft before the branch"
  : >"$GH_LOG"
  t_run env GH_TOKEN=t SCENARIO=pr-draft "$SCRIPTS/sync_remote.sh" a
  t_rc 0
  t_out "a: updated pull request #7"
  t_not_logged graphql
  : >"$GH_LOG"
  echo '[]' >"$T/listing.json"
  t_run env GH_TOKEN=t SCENARIO=branch-exists "$SCRIPTS/sync_remote.sh" b
  t_rc 0
  t_logged '^PATCH repos/owner/b/git/refs/heads/ci-sync$'
  t_in "$T/ref.txt" force=true
}

test_refuses_an_unknown_target_before_writing() {
  fake_github
  fixture
  t_run env GH_TOKEN=t "$SCRIPTS/sync_remote.sh" a nope
  t_rc 1
  t_out "repos/ has no target nope"
  t_not_logged .
}

test_source_sha_defaults_to_this_tree_head() {
  fake_github
  fixture
  t_run env GH_TOKEN=t "$SCRIPTS/sync_remote.sh" a
  t_rc 0
  t_in "$T/commit.json" 'Source: unknown'
  t_git "$T/tree" init -q
  t_git "$T/tree" commit -q --allow-empty -m tree
  t_run env GH_TOKEN=t "$SCRIPTS/sync_remote.sh" a
  t_in "$T/commit.json" "Source: $(git -C "$T/tree" rev-parse HEAD)"
}

test_dry_run_reports_and_writes_nothing() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=unprotected "$SCRIPTS/sync_remote.sh" --dry-run
  t_rc 0
  t_out "a: new.sh differs" "b: in line with files/"
  t_not_logged '^(POST|PATCH) '
  t_not_logged 'rules/branches'
}

test_drift_fails_a_target_differing_with_no_pull_request_open() {
  fake_github
  fixture
  local md="$T/summary.md"
  t_run env GH_TOKEN=t SCENARIO=unprotected GITHUB_STEP_SUMMARY="$md" "$SCRIPTS/sync_remote.sh" --drift
  t_rc 1
  t_out "a: differs from files/ with no sync pull request open" "b: in line with files/" \
    "::error title=drift::a: differs from files/ with no sync pull request open"
  t_not_logged '^(POST|PATCH) '
  t_not_logged 'rules/branches'
  # shellcheck disable=SC2016 # literal text
  t_in "$md" '## Sync (drift check)' "Drifted on \`dev\`, with no sync pull request open:" '- `new.sh`'
  : >"$md"
  t_run env GH_TOKEN=t SCENARIO=pr-open GITHUB_STEP_SUMMARY="$md" "$SCRIPTS/sync_remote.sh" --drift
  t_rc 0
  t_out "a: differs; sync pull request #7 is open"
  t_no_out "::error"
  t_in "$md" "Differs on \`dev\`; pull request [#7](https://example.invalid/pull/7) is open:"
}

test_an_unprotected_target_gets_nothing_and_the_others_sync() {
  fake_github
  fixture
  echo '[]' >"$T/listing.json"
  t_run env GH_TOKEN=t SCENARIO=unprotected-a "$SCRIPTS/sync_remote.sh"
  t_rc 1
  t_out "a: branch protection failed the check; nothing was written" \
    "::error title=sync a::sync failed" "b: opened pull request #8"
  t_not_logged '^(POST|PATCH) repos/owner/a/'
  t_logged '^POST repos/owner/b/pulls$'
}

test_writes_each_target_with_its_own_token() {
  fake_github
  fixture
  echo '[]' >"$T/listing.json"
  t_run env SYNC_TOKEN_B=tb "$SCRIPTS/sync_remote.sh"
  t_rc 1
  t_out "no token: SYNC_TOKEN_A is not set" "::error title=sync a::sync failed" "b: opened pull request #8"
  t_eq "$(cut -d' ' -f1 "$T/tokens.log" | sort -u)" tb "the tokens used"
  t_not_logged 'repos/owner/a/'
}

test_a_failed_call_stops_that_target_alone() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=tree-error "$SCRIPTS/sync_remote.sh"
  t_rc 1
  t_out "::error title=sync a::sync failed, see the lines above" "b: in line with files/"
  t_not_logged 'git/commits$|git/refs|pulls'
}

test_a_commit_github_stored_differently_fails_the_target() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=bad-commit "$SCRIPTS/sync_remote.sh" a
  t_rc 1
  t_out "the commit came back as 1111111111111111111111111111111111111111, not the"
  t_not_logged 'git/refs|pulls'
}

test_an_unverified_signature_fails_the_target() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=unverified "$SCRIPTS/sync_remote.sh" a
  t_rc 1
  t_out "GitHub did not verify the commit's signature: no_user"
  t_not_logged 'git/refs|pulls'
}

test_writes_nothing_without_a_signing_key_and_identity() {
  fake_github
  fixture
  local var
  for var in SYNC_SIGNING_KEY SYNC_COMMITTER_NAME SYNC_COMMITTER_EMAIL; do
    t_run env -u "$var" GH_TOKEN=t "$SCRIPTS/sync_remote.sh"
    t_rc 1
    t_out "$var is not set; the sync commits are signed"
  done
  ssh-keygen -q -t ed25519 -N secret -f "$T/locked"
  t_run env GH_TOKEN=t SYNC_SIGNING_KEY="$(cat "$T/locked")" "$SCRIPTS/sync_remote.sh"
  t_rc 1
  t_out "SYNC_SIGNING_KEY is not an unencrypted OpenSSH private key"
  t_not_logged .
}

test_a_blob_github_stored_differently_fails_the_target() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=bad-blob "$SCRIPTS/sync_remote.sh" a
  t_rc 1
  t_out "came back as 0000000000000000000000000000000000000000"
  t_not_logged 'git/trees$'
}

test_writes_a_section_per_target_to_the_job_summary() {
  fake_github
  fixture
  local md="$T/summary.md"
  t_run env GH_TOKEN=t SOURCE_SHA=abc123 GITHUB_STEP_SUMMARY="$md" GITHUB_REPOSITORY=owner/shared \
    "$SCRIPTS/sync_remote.sh"
  t_rc 0
  t_file "$md" "$(
    cat <<'EOF'
## Sync

Source commit [`abc123`](https://github.com/owner/shared/commit/abc123).

### a

Pull request [#8](https://example.invalid/pull/8) into `dev` opened:

- `new.sh`

### b

In line with `files/`.

EOF
  )"
  : >"$md"
  t_run env GH_TOKEN=t SCENARIO=pr-open GITHUB_STEP_SUMMARY="$md" "$SCRIPTS/sync_remote.sh" a
  t_rc 0
  t_out "a: updated pull request #7"
  # a bare sha outside Actions
  t_in "$md" 'Source commit `' "Pull request [#7](https://example.invalid/pull/7) into \`dev\` updated:"
  : >"$md"
  t_run env GH_TOKEN=t GITHUB_STEP_SUMMARY="$md" "$SCRIPTS/sync_remote.sh" --dry-run a
  t_rc 0
  # shellcheck disable=SC2016 # literal text
  t_in "$md" '## Sync (dry run)' "Differs on \`dev\`; nothing written:" '- `new.sh`'
  : >"$md"
  t_run env GH_TOKEN=t SCENARIO=tree-error GITHUB_STEP_SUMMARY="$md" "$SCRIPTS/sync_remote.sh" a
  t_rc 1
  t_in "$md" 'Failed; nothing written. See the log.'
  t_not_in "$md" 'Pull request'
}

test_a_truncated_tree_listing_fails_the_target() {
  fake_github
  fixture
  t_run env GH_TOKEN=t SCENARIO=truncated "$SCRIPTS/sync_remote.sh" b
  t_rc 1
  t_out "b: the tree listing of main is truncated"
}

t_main
