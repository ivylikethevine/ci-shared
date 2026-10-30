# ci-shared

The one source for the CI files several repositories carry byte-identical:
composite actions, helper scripts, lint configs, the Markdown tool lockfile and
a few workflows. Each repository keeps its own copy, so local runs, editors,
Scorecard and zizmor see ordinary files; nothing in a target refers back here.
[USAGE.md](USAGE.md) lists which repositories receive each file.

## Using an action from another repository

A repository outside the sync can call a composite action here directly,
pinned to a commit like any other action. Use the `files/` path: the
`.github/actions/` entries of this repository are symlinks, which the runner
does not preserve on every platform.

```yaml
- uses: ivylikethevine/ci-shared/files/.github/actions/upsert-tracking-issue@<40-char sha> # <tag>
  with:
    label: tool-versions
    label-color: 0E8A16
    label-description: A pin is behind its upstream release
    title: Pinned tools and dependencies are behind upstream
    resolved: ${{ steps.check.outputs.problems == '0' }}
    close-comment: Every pin is current again.
    body-file: ${{ runner.temp }}/issue.md
```

`advisory-note`, `fetch-latest-artifact`, `mark-tree` and
`upsert-tracking-issue` need nothing else: each uses `github.token` and reads
no file of this repository. `setup-tool` and `setup-tools` read `tools.txt`
beside the action, in `files/` the unrendered template with every target's
rows; a caller with a roster of its own sets `CI_TOOLS_TXT` on the step to it.
The scripts under
`.github/scripts/` and `actions/apt/lib.sh` cannot be called this way; copy
them, or make the repository a target.

## Layout

| Path                          | Holds                                                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `files/`                      | the master copies, at the path they have in a target                                                                                  |
| `repos/<name>.toml`           | one target: its repository, sync branch, files, template and ruleset values                                                           |
| `repos/_base.toml`            | the files most targets receive; a target takes them with `base = true`, less its `skip`                                               |
| `USAGE.md`                    | each file against the repositories receiving it, written from `repos/`                                                                |
| `scripts/check.sh`            | the shipped checks, run over this repository and `files/`                                                                             |
| `scripts/config.py`           | validates `repos/` and prints it as JSON, for the scripts to read                                                                     |
| `scripts/usage.sh`            | writes `USAGE.md`; `--check` fails when it is stale                                                                                   |
| `scripts/census.sh`           | groups the CI and tooling files local checkouts share by content, to find drift                                                       |
| `scripts/sync_local.sh`       | copies `files/` into the checkouts beside this one                                                                                    |
| `scripts/sync_remote.sh`      | opens or updates a pull request per target through the GitHub API                                                                     |
| `scripts/check_protection.sh` | fails unless each target's `main` and `dev` are protected from its token                                                              |
| `scripts/rulesets.sh`         | renders `rulesets/` for a target, or diffs it against the live rulesets                                                               |
| `scripts/sync_prs.sh`         | reports each target's open sync pull request: its age and its checks                                                                  |
| `scripts/own_files.sh`        | writes this repository's own copies of the shared files it uses                                                                       |
| `docs/SECURITY.md`            | what is in scope here and how to report a vulnerability privately                                                                     |
| `rulesets/`                   | the rulesets every target shares, in GitHub's import format                                                                           |
| `rulesets/self.toml`          | this repository's own values in the shared `main` ruleset                                                                             |
| `scratch/`                    | analysis scripts kept for reuse, each with its suite under `tests/`                                                                   |
| `tests/`                      | a suite per script, run against fixtures and a fake `gh`                                                                              |
| `requirements-dev.in`         | the Python dev tools (constricter, pip-audit, reuse, and coverage.py from `requirements-coverage.in`); each `.txt` is its hashed lock |
| `pyproject.toml`              | those tools' settings                                                                                                                 |
| `.github/workflows/`          | `sync.yml`, `checks.yml` and copies of four shared ones                                                                               |

A file belongs here once two targets hold it byte-identical. Per-repository
files stay in their repository: `check_tool_versions.local.sh`, the
bug-report and feature-request forms, and every workflow that differs. `setup-tool/tools.txt` and
`dependabot.yml` are the exceptions: a target's own rows and entries live here
too, in its `shared:if repo=<name>` blocks, so any change to them is an edit
here.

## Changing a shared file

1. Edit it under `files/`. To share a new file, copy it in, add its path to
   `repos/_base.toml` (and the `skip` of each target that should not receive
   it) or to the `files` list of each `repos/<name>.toml` that should, and run
   `scripts/usage.sh`. After a change to a file this repository keeps its own
   copy of (`OWN` in `scripts/own_files.sh`), run `scripts/own_files.sh`.
2. Run `scripts/check.sh`.
3. `scripts/sync_local.sh --check` lists the checkouts that differ. The
   checkouts themselves are left alone: the sync pull requests of step 4 carry
   the change.
4. Once this repository is on GitHub, a push to `main` that changes `files/`
   or `repos/` opens one draft pull request per target on branch `ci-sync`,
   and re-pushes update it. The target's CI skips drafts, so it runs once the
   pull request is marked ready. A change to the scripts alone, `ci_render` included,
   syncs on the next manual run of `sync.yml`. The run's job summary lists
   each target's pull request and the files it changes.

`scripts/census.sh --drift` lists every CI or tooling path whose copies
disagree across the local checkouts, shared here or not; `--gaps` lists, per shared
file, the targets holding a copy their `repos/<name>.toml` does not list (which
the sync never refreshes) and the targets holding none. On GitHub, the weekly
`sync.yml` run's `scripts/sync_remote.sh --drift` fails for each target whose
shared files differ from `files/` with no sync pull request open: one edited
by hand, or whose pull request was closed unmerged. The same run's
`scripts/rulesets.sh diff` fails for each target whose rulesets differ from
`rulesets/`, and `scripts/sync_prs.sh` for each sync pull request with a failed
check, no checks, or open over two weeks, so a shared file that breaks a target
shows up here. The last is off until the repository variable `SYNC_PR_REPORT`
(_Settings → Secrets and variables → Actions → Variables_) is `true`, which
waits on the sync App's Checks and Commit statuses read. These and the token
and protection checks keep one `sync-health` issue open until a weekly run
passes.

Sync pull requests go into each target's `main`, so its CI and CodeQL check
them once, Scorecard's CI-Tests and SAST checks credit the synced commits, and
the scheduled workflows run the new files as soon as they merge. Merge `main`
back into `dev` after one merges; `dev` takes signed direct pushes.

## Roadmap

[docs/ROADMAP.md](docs/ROADMAP.md): fixes, dated platform changes, candidate
integrations and replacements, files that could join `files/`, and checks this
repository could run on itself, each with what to verify first.

## Templates

A file that differs between targets only by a few values or lines is a
template. Its copy in `files/` spells a value `__key__` and marks lines kept
only when a key is set (`shared:if key`), unset (`shared:unless key`) or has
one of a few values (`shared:if key=a,b`), up to `shared:endif`; a
`shared:else` between them keeps the other lines instead. Blocks nest, and a
marker is a `#` comment line, or `<!-- shared:if key -->` in Markdown. The target's
`[templates."<path>"]` table sets the values: words separated by single spaces,
holding no `%`, `&` or `\`. Its `[values]` table sets values every template it
receives takes, such as its language; a path's table may not repeat one. The
key `repo` is always set, to the target's name, so a file may spell `__repo__`
or `shared:if repo=<name>` with no table.

```toml
[values]
language = "rust"

[templates.".github/workflows/advisories.yml"]
tool = "cargo-deny"
```

Every script renders before comparing or copying, so a target never sees a
marker, and `scripts/check.sh` lints each template as every target receives it
(actionlint and `lint_workflows.sh` for a workflow, markdownlint for Markdown,
prettier for both) and fails when a rendering still holds a `__key__` some
target sets. A Markdown template is skipped by the lint over the raw tree,
since its markers break the list structure around them. A workflow template
is skipped by the raw `lint_workflows.sh` run, since a block may hold a value a
target chooses, such as an egress policy; actionlint and zizmor still read it
raw.

## Checking this repository

This repository runs the checks it ships, on itself and on `files/`. The lint
configs at the root, `.github/zizmor.yml`, `.github/package.json` and its lock,
and the helpers under `.github/actions/` and `.github/scripts/` are symlinks
into `files/`, so there is one copy of each; `.github/actions/setup-tool/tools.txt`
is the unrendered template, so the version check reads every target's pins.
One file is this repository's own:
`.github/scripts/check_tool_versions.local.sh` points the version check at the
Markdown tools' and Python tools' manifests and the action pins under `files/`.

It runs four of the workflows it ships, as its targets do: `codeql.yml` (the
`actions` language alone), `scorecard.yml`, `link-check.yml` and
`tool-versions.yml`, the last three following `checks.yml`, which is named `CI`
for them. Its `tool-versions.yml`, `dependabot.yml` and `.gitignore` are the
templates rendered for `repo=ci-shared`. A workflow or a `.gitignore` cannot be
a symlink, and a template's markers must not reach a copy, so
`scripts/own_files.sh` writes each as a copy, the other workflows rendered with
no values, and `scripts/check.sh` fails when one is stale.

Every script and Python file here, `scratch/` included, has a test suite with
100% coverage, and the Python passes constricter at `suffocate`. A scratch
script that is not worth a suite is run from a temporary directory and not
kept.

- `scripts/check.sh` runs shellcheck, shfmt, constricter, actionlint,
  `lint_workflows.sh`, zizmor, prettier, markdownlint, lychee offline over the
  tracked Markdown, typos, gitleaks over the
  history, `reuse lint`, pip-audit over `requirements-dev.txt` and npm audit over the
  Markdown tools' lock (less the advisories `files/.github/osv-scanner.toml`
  accepts, as `advisories.yml` reads it), `scripts/usage.sh --check`,
  `scripts/own_files.sh --check`, and a check that `files/.gitignore`
  (every target's block active here) ignores no shared file;
  `checks.yml` runs it on every push and pull request. Locally it needs the
  `tools.txt` pins on `PATH`, `npm ci --prefix .github` once, and
  `requirements-dev.txt` in a virtual environment whose `bin/` is on `PATH`:
  `python3 -m venv local/venv && local/venv/bin/pip install --require-hashes --no-deps -r requirements-dev.txt`.
- `.github/scripts/check_tool_versions.sh` reports every pin behind the newest
  release past the cooldown; `tool-versions.yml` runs it weekly and keeps a
  `tool-versions` issue open while one is behind.
- `tests/run.sh [SUITE...]` runs the suites (`T_ONLY=<regex>` picks tests
  within one); each builds its own fixture tree and points the scripts at it
  through `CI_SHARED_DIR`. `tests/coverage.sh` runs them under kcov and
  coverage.py and fails unless every statement of `scripts/*.sh` and
  `scratch/*.sh` ran and every line and branch of the Python did;
  `checks.yml`'s coverage job runs it. It needs upstream kcov 43 or later
  (`tools.txt`'s row; Ubuntu's `43+dfsg-2` records no hit on a multi-line
  array assignment), the `shfmt` and `yq` pins and the virtual environment
  above; `tests/coverage.py` explains how
  kcov's line counts are mapped to statements.

## The sync App

The sync writes through a GitHub App the repository owner creates and
installs (_Settings → Developer settings → GitHub Apps → New GitHub App_), no
webhook, installable only on this account, and installed on every target.
Each `sync.yml` run mints one installation token per target with
`actions/create-github-app-token`, scoped to that repository alone, valid
for an hour at most and revoked when the job ends. Nothing expires to renew.

- **Permissions:** Contents read and write (a pull request needs its branch
  pushed), Pull requests read and write, Workflows read and write (the synced
  files include `.github/workflows/`), Checks read and Commit statuses read
  (`scripts/sync_prs.sh` reads the checks on the sync pull request, once
  `SYNC_PR_REPORT` turns it on); Metadata read is added automatically. No
  Administration permission: without it, GitHub hides a ruleset's
  `bypass_actors`, which `scripts/rulesets.sh diff` then compares without, and
  `scripts/check_protection.sh` reads the bypass that matters, the App's own.
  Each mint step requests exactly these, so a permission granted to the App
  later reaches the tokens only once the steps request it too, and one the App
  lacks fails the mint.
- **Credentials:** the `sync` environment holds the App's client ID as the
  variable `SYNC_APP_CLIENT_ID` and one of its private keys, the whole PEM
  file, as the secret `SYNC_APP_PRIVATE_KEY`. The environment's _Deployment
  branches and tags_ are limited to `main`, so a run from any other ref cannot
  read them.

The scripts read target `<name>`'s token as `SYNC_TOKEN_<NAME>`, the name in
capitals with `-` as `_` (`SYNC_TOKEN_SAY_HI`). In `sync.yml`, a mint step
per target feeds a `TOKEN_<NAME>` line of the `tokens` step, which exports
each as `SYNC_TOKEN_<NAME>`. A new target needs the App installed on it, its
mint step and its `TOKEN_<NAME>` line; until then the `tokens` step fails and
the sync skips it. The job's `env` passes its own token as
`SYNC_TOKEN_CI_SHARED`, for this repository's protection and rulesets checks;
it is no secret, and no sync writes with it.

Contents write lets a token push any branch of its target, not just
`ci-sync`. The rulesets on each target's `main` and `dev` keep it to pull
requests, provided the App can bypass them only through a pull request; it is
no bypass actor, so it cannot. `scripts/check_protection.sh` checks this and
fails closed on any error; `scripts/sync_remote.sh` runs it on each target
before writing to it, and a target that fails gets nothing while the others
still sync.

For a local run, `GH_TOKEN` stands in for any target whose `SYNC_TOKEN_<NAME>`
is unset.

## The signing key

Both rulesets require signed commits, and GitHub blocks every merge method
while a pull request holds an unsigned one, so `sync_remote.sh` signs each
sync commit. The key is an SSH key used for nothing else:

- **Private half:** the `sync` environment's secret `SYNC_SIGNING_KEY`, the
  whole OpenSSH key file, without a passphrase.
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
checks (each `{ context = "<name>" }`, with an `integration_id` only when an
app other than GitHub Actions reports it), the code scanning tools, the
coverage floor and whether code quality is gated.

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
`scripts/rulesets.sh diff [NAME...]` shows where the live ones differ, and
the weekly `sync.yml` run fails on any.

This repository's own `main` is held to the same `main` ruleset, with the
values in `rulesets/self.toml` (`render ci-shared main`), since a push to it
opens a pull request in every target; its `dev` and tags are not. The weekly
run reads it, and `scripts/check_protection.sh` checks its `main`, with the
job's own read-only token, passed as `SYNC_TOKEN_CI_SHARED`.

Two repository settings sit beside the rulesets, set by hand in each
repository with an admin token:

- **Actions pinned to a full-length commit SHA**, in every repository
  (_Settings → Actions → General_):
  `gh api -X PUT repos/OWNER/REPO/actions/permissions -F enabled=true -f allowed_actions=ALLOWED -F sha_pinning_required=true`,
  ALLOWED being the `allowed_actions` a GET of the same path returns, so the
  PUT changes nothing else. GitHub then refuses an unpinned `uses:` at run time, on every branch; a
  reusable workflow stays exempt. `lint_workflows.sh` rule 5 checks the same
  in-tree.
- **Immutable releases**, where `repos/<name>.toml` sets
  `immutable_releases = true` (_Settings → General → Releases_):
  `gh api -X PUT repos/OWNER/REPO/immutable-releases`. A published release's
  tag and assets are then locked, so a release workflow must attach every
  asset while the release is a draft and publish it last; `gh release create`
  with its assets does.

`scripts/rulesets.sh diff` compares both, but GitHub shows them only to a
token with Administration read, which the sync App lacks: the weekly run
names them as hidden, and a local run with an admin token compares them.
