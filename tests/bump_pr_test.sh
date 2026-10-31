#!/usr/bin/env bash
# scripts/bump_pr.sh against a fixture checkout and a fake `gh api`: one verified
# commit on the checkout's HEAD, the branch made or moved, and the pull request
# opened or updated.
# shellcheck disable=SC2329 # t_main calls the test_* functions by name
# shellcheck disable=SC2016 # the backticks are the body's Markdown
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A checkout at $T/tree with one committed file, and the patch changing it. BRANCH
# set means the branch exists, PR its open pull request, UNVERIFIED a commit GitHub
# did not verify, BAD_BLOB a blob stored with other bytes.
fixture() {
  export GITHUB_REPOSITORY=owner/repo
  t_git "$T/tree" init -q
  printf 'one\n' >"$T/tree/pins.txt"
  mkdir -p "$T/tree/s"
  printf 'x\n' >"$T/tree/s/run.sh"
  chmod +x "$T/tree/s/run.sh"
  t_git "$T/tree" add pins.txt s/run.sh
  t_git "$T/tree" commit -qm base
  printf 'two\n' >"$T/tree/pins.txt"
  printf 'y\n' >"$T/tree/s/run.sh"
  t_git "$T/tree" diff --binary >"$T/bumps.patch"
  t_git "$T/tree" checkout -q -- pins.txt s/run.sh
  echo '- `tool` 1 to 2' >"$T/body.md"
  t_fake_gh <<'EOF'
case "$method $ep" in
"POST repos/owner/repo/git/blobs")
  [ -z "${BAD_BLOB:-}" ] || { reply '{"sha": "wrong"}'; exit 0; }
  sha="$(jq -r .content <<<"$input" | base64 -d | git hash-object --stdin)"
  reply "{\"sha\": \"$sha\"}"
  ;;
"POST repos/owner/repo/git/trees")
  echo "$input" >"$T/tree.json"
  reply '{"sha": "newtree"}'
  ;;
"POST repos/owner/repo/git/commits")
  echo "$input" >"$T/commit.json"
  if [ -n "${UNVERIFIED:-}" ]; then
    reply '{"sha": "newcommit", "verification": {"verified": false, "reason": "unsigned"}}'
  else
    reply '{"sha": "newcommit", "verification": {"verified": true, "reason": "valid"}}'
  fi
  ;;
"GET repos/owner/repo/git/ref/heads/tool-bumps")
  [ -n "${BRANCH:-}" ] || fail "HTTP 404"
  reply '{"object": {"sha": "old"}}'
  ;;
"PATCH repos/owner/repo/git/refs/heads/tool-bumps") printf '%s\n' "${fields[@]}" >"$T/ref.log" ;;
"POST repos/owner/repo/git/refs") printf '%s\n' "${fields[@]}" >"$T/ref.log" ;;
"GET repos/owner/repo/pulls?head=owner:tool-bumps&base=main&state=open")
  if [ -n "${PR:-}" ]; then reply "[{\"number\": $PR}]"; else reply '[]'; fi
  ;;
"PATCH repos/owner/repo/pulls/"*) printf '%s\n' "${fields[@]}" >"$T/pr.log" ;;
"POST repos/owner/repo/pulls")
  printf '%s\n' "${fields[@]}" >"$T/pr.log"
  reply '{"number": 7}'
  ;;
*) fail "HTTP 404 $method $ep" ;;
esac
EOF
}

test_a_first_run_makes_the_branch_and_opens_a_draft() {
  fixture
  head="$(git -C "$T/tree" rev-parse HEAD)"
  t_run "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 0
  t_out "opened pull request #7"
  t_eq "$(jq -c '[.parents, .tree, .author]' "$T/commit.json")" "[[\"$head\"],\"newtree\",null]" "the commit"
  # each changed file at its own mode, on the checkout's tree
  t_eq "$(jq -r '.base_tree' "$T/tree.json")" "$(git -C "$T/tree" rev-parse 'HEAD^{tree}')" "the base tree"
  t_eq "$(jq -c '[.tree[] | [.path, .mode]]' "$T/tree.json")" '[["pins.txt","100644"],["s/run.sh","100755"]]' "the entries"
  t_in -x "$T/ref.log" 'ref=refs/heads/tool-bumps' 'sha=newcommit'
  t_in -x "$T/pr.log" 'title=ci: bump pinned tools' 'head=tool-bumps' 'base=main' 'draft=true' 'body=- `tool` 1 to 2'
}

test_a_later_run_moves_the_branch_and_updates_the_pull_request() {
  fixture
  BRANCH=1 PR=5 t_run "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 0
  t_out "updated pull request #5"
  t_in -x "$T/ref.log" 'sha=newcommit' 'force=true'
  t_in -x "$T/pr.log" 'body=- `tool` 1 to 2'
  t_not_logged '^POST repos/owner/repo/pulls$'
}

test_an_unverified_commit_moves_nothing() {
  fixture
  t_run env UNVERIFIED=1 "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 1
  t_out "GitHub did not verify the commit's signature: unsigned"
  t_not_logged 'git/ref'
}

test_a_blob_with_other_bytes_fails() {
  fixture
  t_run env BAD_BLOB=1 "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 1
  t_out "came back as wrong"
  t_not_logged 'git/commits'
}

test_a_deleted_file_fails() {
  fixture
  git -C "$T/tree" rm -q --cached pins.txt
  t_git "$T/tree" commit -qm drop
  printf 'one\n' >"$T/tree/gone.txt"
  t_git "$T/tree" add gone.txt
  t_git "$T/tree" commit -qm gone
  rm "$T/tree/gone.txt"
  t_git "$T/tree" diff --binary >"$T/bumps.patch"
  t_git "$T/tree" checkout -q -- gone.txt
  t_run "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 1
  t_out "gone.txt is no file; a bump only edits files"
}

test_an_empty_patch_writes_nothing() {
  fixture
  : >"$T/bumps.patch"
  t_run "$SCRIPTS/bump_pr.sh" "$T/bumps.patch" "$T/body.md"
  t_rc 0
  t_out "nothing to bump"
  t_not_logged '.'
}

test_usage() {
  t_run "$SCRIPTS/bump_pr.sh"
  t_rc 2
  t_out "usage: bump_pr.sh <patch> <body file>"
}

t_main
