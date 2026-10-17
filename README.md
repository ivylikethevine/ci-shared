<!-- SPDX-License-Identifier: MIT -->

# ci-shared

The one source for the CI files several repositories carry byte-identical:
composite actions, helper scripts, lint configs, the Markdown tool lockfile and
a few workflows. Each repository keeps its own copy, so local runs, editors,
Scorecard and zizmor see ordinary files; nothing in a target refers back here.
[USAGE.md](USAGE.md) lists which repositories receive each file.

## Layout

| Path                          | Holds                                                                       |
| ----------------------------- | --------------------------------------------------------------------------- |
| `files/`                      | the master copies, at the path they have in a target                        |
| `repos/<name>.toml`           | one target: its repository, sync branch, files, template and ruleset values |
| `USAGE.md`                    | each file against the repositories receiving it, written from `repos/`      |
| `scripts/check.sh`            | the shipped checks, run over this repository and `files/`                   |
| `scripts/config.py`           | validates `repos/` and prints it as JSON, for the scripts to read           |
| `scripts/usage.sh`            | writes `USAGE.md`; `--check` fails when it is stale                         |
| `scripts/spdx.sh`             | adds the SPDX license comment; `--check` fails when a file lacks it         |
| `scripts/census.sh`           | groups the CI files local checkouts share by content, to find drift         |
| `scripts/sync_local.sh`       | copies `files/` into the checkouts beside this one                          |
| `scripts/sync_remote.sh`      | opens or updates a pull request per target through the GitHub API           |
| `scripts/check_protection.sh` | fails unless each target's `main` and `dev` are protected from its token    |
| `scripts/check_tokens.sh`     | prints when each target's sync token expires, failing within two weeks      |
| `scripts/rulesets.sh`         | renders `rulesets/` for a target, or diffs it against the live rulesets     |
| `rulesets/`                   | the rulesets every target shares, in GitHub's import format                 |
| `tests/`                      | a suite per script in `scripts/`, run against fixtures and a fake `gh`      |
| `.github/workflows/`          | `sync.yml`, `checks.yml` and `tool-versions.yml`                            |

A file belongs here once two targets hold it byte-identical. Per-repository
files stay in their repository: `setup-tool/tools.txt`,
`check_tool_versions.local.sh`, `dependabot.yml`, the issue and PR templates,
and every workflow that differs.

## Changing a shared file

1. Edit it under `files/`. To share a new file, copy it in, add its path to
   the `files` list of each `repos/<name>.toml` that should receive it, and run
   `scripts/usage.sh`.
2. Run `scripts/check.sh`.
3. `scripts/sync_local.sh --check` lists the checkouts that differ;
   `scripts/sync_local.sh` copies the change into them, leaving any path with
   uncommitted changes alone.
4. Once this repository is on GitHub, a push to `main` that changes `files/`
   or `repos/` opens one pull request per target on branch `ci-sync`, and
   re-pushes update it. A change to the scripts alone, `ci_render` included,
   syncs on the next manual run of `sync.yml`.

`scripts/census.sh --drift` lists every CI path whose copies disagree across
the checkouts, shared here or not.

A target's CI and CodeQL workflows trigger on pull requests into `dev` as well
as `main`, so the sync pull request is checked before it merges. Scorecard's
CI-Tests and SAST checks grade each commit on `main` by the first pull request
it was merged through, which for a synced commit is the one into `dev`; a
target whose workflows run only for `main` loses a point on both.

## Templates

A file that differs between targets only by a few values is a template. Its
copy in `files/` spells a value `__key__` and marks lines kept only when a key
is set (`# shared:if key`) or unset (`# shared:unless key`), up to
`# shared:endif`. A target's row sets the values after the path:

```text
.github/workflows/codeql.yml language=rust Language=Rust
```

Every script renders before comparing or copying, so a target never sees a
marker, and `scripts/check.sh` lints each workflow template as every target
receives it. Values cannot hold spaces.

## To do

- python-constricter keeps its own `.markdownlint.yaml` and `.prettierrc.yaml`
  (prettier rewraps prose at 100, MD013 at 100). Move it to the shared
  hand-wrapped copies, whose checks its docs already pass unchanged, and make
  their comments generic first: they name Zed, `.moxide.toml` and
  `_config.yml`, which python-constricter does not have. Until then, prettier
  at its `printWidth: 100` rewraps the shared workflows it receives; its CI
  runs prettier over Markdown alone, so only an editor's format-on-save shows
  it.

## Checking this repository

This repository runs the checks it ships, on itself and on `files/`. The lint
configs at the root, `.github/zizmor.yml`, `.github/package.json` and its lock,
and the helpers under `.github/actions/` and `.github/scripts/` are symlinks
into `files/`, so there is one copy of each. Two files are this repository's
own: `.github/actions/setup-tool/tools.txt` pins the lint tools, and
`.github/scripts/check_tool_versions.local.sh` points the version check at the
Markdown tools' manifest and adds a second run over `files/`.

- `scripts/check.sh` runs shellcheck, shfmt, actionlint, `lint_workflows.sh`,
  zizmor, prettier, markdownlint, `scripts/usage.sh --check` and
  `scripts/spdx.sh --check`; `checks.yml` runs it on every push and pull
  request. Locally it needs the `tools.txt` pins on `PATH` and
  `npm ci --prefix .github` once.
- `.github/scripts/check_tool_versions.sh` reports every pin behind the newest
  release past the cooldown; `tool-versions.yml` runs it weekly.
- `tests/run.sh [SUITE...]` runs the suites (`T_ONLY=<regex>` picks tests
  within one); each builds its own fixture tree and points the scripts at it
  through `CI_SHARED_DIR`. `tests/coverage.sh` runs them under kcov and fails
  unless every statement of `scripts/*.sh` ran; `checks.yml`'s coverage job
  runs it. It needs the `kcov` and `shfmt` pins; `tests/coverage.py` explains
  how kcov's line counts are mapped to statements.

## The sync tokens

Each target has its own token, in a repository secret of this repository
named for it: `SYNC_TOKEN_<NAME>`, the target's name in capitals with `-` as
`_` (`SYNC_TOKEN_SAY_HI`). _Settings → Secrets and variables → Actions → New
repository secret_ holds each one, a fine-grained personal access token:

- **Repository access:** that target alone.
- **Permissions:** Contents read and write (a pull request needs its branch
  pushed), Pull requests read and write, Workflows read and write (the synced
  files include `.github/workflows/`); Metadata read is added automatically.
- **Expiry:** the shortest you will renew. `scripts/check_tokens.sh` reads each
  token's expiry from GitHub and fails once one is within two weeks of it;
  `sync.yml` runs it on every run and weekly, so the weekly run fails in time
  to renew.

A new target needs its secret and its line in `sync.yml`'s job `env`, which
passes each secret by name; until then `check_tokens.sh` reports it unset and
the sync skips it.

Contents write lets a token push any branch of its target, not just
`ci-sync`. The rulesets on each target's `main` and `dev` keep it to pull
requests, provided the token's user can bypass them only through a pull
request: the token acts as that user. `scripts/check_protection.sh` checks
this and fails closed on any error; `scripts/sync_remote.sh` runs it on each
target before writing to it, and a target that fails gets nothing while the
others still sync.

For a local run, `GH_TOKEN` stands in for any target whose `SYNC_TOKEN_<NAME>`
is unset; `check_tokens.sh` reads only the `SYNC_TOKEN_<NAME>` variables.

## The signing key

Both rulesets require signed commits, and GitHub blocks every merge method
while a pull request holds an unsigned one, so `sync_remote.sh` signs each
sync commit. The key is an SSH key used for nothing else:

- **Private half:** the repository secret `SYNC_SIGNING_KEY`, the whole
  OpenSSH key file, without a passphrase.
- **Public half:** a signing key (_Settings → SSH and GPG keys → New SSH key →
  Key type: Signing Key_) of the account whose verified email `sync.yml` sets
  as `SYNC_COMMITTER_EMAIL`. It stays out of `.github/allowed_signers`, which
  gates release tags.

The script recomputes the commit object it signed and fails a target, before
moving its branch, when GitHub's copy hashes differently or GitHub does not
verify it. A local run sets `SYNC_SIGNING_KEY`, `SYNC_COMMITTER_NAME` and
`SYNC_COMMITTER_EMAIL` itself; `--dry-run` needs none of them.

## The rulesets

`rulesets/main.json`, `rulesets/dev.json` and `rulesets/stable.json` are the
rulesets every target shares; the `[rulesets.main]` table of
`repos/<name>.toml` holds what is a target's own on `main`: the required status
checks, the code scanning tools, the coverage floor and whether code quality is
gated.

- **`main`:** no force push or deletion, signed commits, a pull request with
  checks passing on an up-to-date branch, merge or squash. Repository admins
  bypass it only through a pull request.
- **`dev`:** no force push or deletion, signed commits, no bypass. Direct
  pushes stay open to signed commits.
- **`stable`** (`protect-stable`, the `v*` and `*-rc` tags): no move or
  deletion, signed commits, no bypass.

No review approval is required, so the repository owner merges their own pull
requests; Scorecard's Branch-Protection check scores that 3/10, and a required
approval would lift it to 8/10.

`scripts/rulesets.sh render <name> main|dev|stable` prints a ruleset to import
(_Settings → Rules → Rulesets → New ruleset → Import a ruleset_);
`scripts/rulesets.sh diff [NAME...]` shows where the live ones differ.
