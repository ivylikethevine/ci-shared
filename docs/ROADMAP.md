# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone.

## Order of work

Ranked by value for size; the numbers are the items below. S, M and L are sizes.

1. 1.3, commit and merge each repository's part; the sync PRs carry the
   `files/` half, and the stale `setup-tool/action.yml` in each target goes
   after them (S).
2. 5.3's rescan of the lowered limits, due since 2026-11-08 (S).
3. 3.1, the 2026-11-09 weekly run, which closes #4 if every check passes (S).
4. 3.3, read say-hi's and instadroid's next tag run (S).
5. 5.1, a `block` job that passes on a westus2 runner in the experiment under
   v2.22.3, or v2.22.4 from 2026-11-13, then the `dns-experiment` step's
   removal (S).
6. 5.3's first automatic rerun on `main`, on the next run that shows it (S).
7. 5.4's check, which needs a real pull request (S).
8. 1.2, the rest of the batch, say-hi first (M, one session per repository).

Waiting on upstream: 1.1, 2.1's runner label, 3.5, 5.2. Not worth doing as
things stand: 3.4.

## 1. Fixes in this repository

### 1.1 The `$/` rewrite and zizmor `self-repository` (_batch_)

- **What:** Scorecard v5.6.0, which `ossf/scorecard-action` v2.5.0 ships,
  reads `uses: $/...` as a local action, so the rewrite of every
  `uses: ./.github/...` to `$/.github/...` and `self-repository` back on in
  `.github/zizmor.yml` could follow. Blocked: actionlint 1.7.12, the newest,
  rejects `$/` ("ref is missing"). Every repository's lint gate runs actionlint.
  [rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711) and pull
  request 732 are open, but its last release is 2026-03-30 and its last commit
  2026-04-19, so a fix may not come. jactionlint accepts it but is not taken for
  now (3.5). Not evaluated: the fork `kjanat/actionlint`, which says it is a
  drop-in CLI with `$/` and `ubuntu-26.04`, and a `paths` ignore in
  `.github/actionlint.yaml` for the two `$/` messages, as #711 suggests.
- **How, once actionlint accepts it:** rewrite the shared workflows and each
  target's own, extend `lint_workflows.sh` rule 7 to `$/` (it checks the
  sparse-checkout list for `./` refs only), re-enable the rule, and update
  each target's disabled-rules note.

### 1.2 harden-runner `block` on macOS and Windows jobs (_batch_)

- **What:** harden-runner v2.20.0 supports `egress-policy: block` on GitHub's
  macOS and Windows runners in the free tier, so those jobs can move from
  `audit`. A weekly external-link check stays `audit`, and Windows arm64 has no
  agent, so those legs stay unmonitored.
- **How:** `scripts/egress_census.sh` lists the jobs and
  `scripts/egress_baseline.sh` reads each job's endpoints from its audit runs
  for `allowed-endpoints`. The jobs live in the targets' own workflows, one
  session per repository; update each disabled-rules row that says only audit
  is supported.

### 1.3 Remove `setup-tool` for `setup-tools` (_batch_, done in the trees 2026-11-08)

- **Done, not committed:** `setup-tool/action.yml` is gone from `files/` and
  `repos/_base.toml`; `install.sh`, `lib.sh` and `tools.txt` stay in
  `setup-tool/` as `setup-tools`' backend, and `install.sh` no longer writes
  `image=` (`resolve.sh` reads `$ImageOS` itself). The shared callers
  (`advisories.yml`, `image-scan.yml`, `link-check.yml`) call `setup-tools`,
  and `image-scan.yml`'s and sharerr-rs `docker.yml`'s sparse lists hold both
  directories. Every target's own caller moved: sharerr-rs `ci.yml` (5, its
  terraform path filter gains `setup-tools/`), `docker.yml` and `coverage.yml`,
  instadroid `publish.yml`, python-constricter `ci.yml` and `security.yml` (3),
  say-hi `usage.yml`, whose `freeze` the release suite's row check now reads.
  say-hi's `test_setup_tool_resolve_names_the_pin` ignores an `image=` line, so
  it passes against either `install.sh` and can land before the sync PR.
  `scripts/check.sh`'s own checks and `tests/run.sh` pass; its tool checks
  (constricter, reuse, pip-audit, gitleaks' version, zizmor online) could not
  run in the session.
- **Left:** the sync writes files and never deletes one, so each target's
  `setup-tool/action.yml` stays until it is removed there, after that target's
  sync PR has merged; until then nothing calls it. Each tool downloads once
  more, since the cache key changes.

### 1.4 The targets' own action SHAs (_batch_, done 2026-11-06)

- **Done, merged in every repository:** every target's own workflows and actions, the files
  the sync does not deliver, are on `files/`' pins or the ones their
  `tool-versions` issues offered: harden-runner v2.22.3 everywhere, this
  repository and `files/` included; docker/login-action v4.7.0, codeql
  upload-sarif v4.39.1, setup-python v7.1.0, rust-cache v2.9.3, setup-uv
  v10.3.2, cibuildwheel v4.3.4 and openbsd-vm v1.4.9 where used.
  `scripts/stale_pins.sh` lists none behind; `scripts/bump_pins.sh` makes the
  next round's edits. `setup-tool`'s `version` and `sha256` inputs went in the
  same round: `install.sh` reads the row's pin and sha256 alone.
- **Override:** markdownlint 0.42.0, which markdownlint-cli2 0.24.0 pulls in, pins
  `re2js` 2.8.6 under GHSA-gg6h-894w-4m9c, fixed in 2.8.7. `overrides` holds
  `re2js` at 2.9.0, the newest past the cooldown; drop it once markdownlint's
  own pin passes the advisory.
- **Left in the issues, not action SHAs:** say-hi's bashcov 4.0.1 and its
  `bash:3.2` digest.

## 2. Platform changes with a date

### 2.1 `ubuntu-latest` becomes Ubuntu 26.04 between 2026-10-19 and 2026-11-19

Every shared workflow job, and this repository's own, now names
`ubuntu-26.04` rather than `ubuntu-latest`, so the next image change is a
commit and not the label moving under a run. `.github/actionlint.yaml`, shared
with every target, tells actionlint 1.7.12 the label; drop it once a release
knows 26.04. What changed under them, from GitHub's image comparison
(`actions/runner-images#14226`):

| Tool           | 24.04    | 26.04                                                           |
| -------------- | -------- | --------------------------------------------------------------- |
| system python3 | 3.12     | 3.14 (3.10, 3.11, 3.13 no longer cached)                        |
| node           | 22       | 24 (22 still cached)                                            |
| docker         | 28.0.4   | 29.4.2, compose 5.1.3                                           |
| cmake          | 3.31.6   | latest                                                          |
| gcc            | 12 to 14 | 13 to 15                                                        |
| removed        |          | miniconda, julia, mercurial, pulumi, fastlane, global npm tools |

- **Runs:** this repository's workflows pass on `ubuntu-26.04`, as do instadroid's
  `main` CI (run 41258224153, 2026-10-31) and `image-scan.yml` under docker 29 in
  sharerr-rs (run 41302164981, 2026-11-01). say-hi's live `main` ruleset requires
  its renamed suite jobs.
- **Kept for it:** `setup-tools`' cache key carries the image name (`ImageOS`), so a
  tool built from source on 24.04 (mandoc) is not restored on 26.04; `apt/lib.sh`
  drops vendor `*.sources` files as well as `*.list`; `checks.yml` takes a
  `runner` input on dispatch.
- **Left:** drop the label from `.github/actionlint.yaml` once an actionlint
  release knows 26.04.

### 2.2 Dependabot's default cooldown

- **What:** since 2026-07-14 Dependabot waits three days by default; the
  shared `dependabot.yml` sets seven explicitly on every entry, which wins.
  Nothing to change; `COOLDOWN_DAYS` in `check_tool_versions.sh` defaults to the
  same seven.

## 3. Integrations and replacements

### 3.1 One GitHub App in place of five fine-grained tokens (live)

- **Done in the tree:** `sync.yml` mints one token per target through
  `actions/create-github-app-token` v3.3.0, `repositories` scoping each to its
  target, and a `tokens` step exports them as the `SYNC_TOKEN_<NAME>` the
  scripts already read, so the scripts and their suites keep their contract.
  `check_tokens.sh` and its suite are gone; the health issue's `tokens` line
  now means the App minted no token for a target. The README's "The sync App"
  section has the permissions and credentials.
- **Keeps:** the SSH signing key and `create_commit`'s verification (the
  signature is checked against the committer email's registered key, not the
  token), `check_protection.sh` (the App is the actor whose bypass is read;
  not a bypass actor, so `never`), the `sync` environment.
- **Live since 2026-10-28:** the App is created and installed, its credentials
  set, and the change merged to `main`. Dry runs 40751549579 (homebrew-tap)
  and 40751746191 (every target) minted all five tokens, and
  `check_protection.sh` passed every target's `main` and `dev` with the App's
  token. Every target was in line with `files/`, so no commit was written.
  The five `SYNC_TOKEN_<NAME>` secrets are deleted and their PATs revoked. The
  first commit written with an App token, homebrew-tap's `db047dd` (pull request
  82), shows as verified.
- **Anchored mint steps:** the mint steps share one `with:` through a YAML anchor,
  reading `repositories` from each step's `env.TARGET`. That form minted all five
  tokens on 2026-11-02, in the push run (41534178362), which opened the sync pull
  requests, and in the weekly run, whose health issue has no `tokens` line.
- **Left:** the `sync-health` issue (#4) is still open. The 2026-11-02 weekly
  run, the first under the App (41540975712), failed only the rulesets diff:
  three live `main` rulesets had dropped entries `repos/` still held. Trivy
  fails on pull requests to main, so it is out of instadroid's and sharerr-rs's
  `code_scanning_tools`; say-hi's checks were restructured, so its two `e2e`
  contexts are out of its required checks. That has been on `main` since #33;
  the 2026-11-09 weekly run closes #4 if every check passes.
- **Still by hand per target:** a mint step in `sync.yml`, which
  `scripts/check.sh` fails without.

### 3.2 Bumps as a pull request, not a hand edit (live)

- **Live:** `.github/workflows/bump-tools.yml`, weekly after the
  version check. `check_tool_versions.sh` stays read-only and lists what is behind
  in `CI_FIX_LIST`; `scripts/apply_bumps.sh` edits it, in this repository alone
  since the sync owns the targets' copies and only this repository's manifest
  kinds are handled: `tools.txt` rows with each asset's sha256, every `uses:`, the
  inline pin, the npm manifest and lock, and the `.in` files and their locks.
  `scripts/bump_pr.sh` writes one draft pull request on `tool-bumps`, in a job of
  its own holding the App's token; a commit naming no author is signed by GitHub
  for the App, so it needs no SSH key and keeps file modes.
- **Runs:** the weekly run of 2026-11-02 (41491501365) found a bump and opened
  pull request 31 (python-constricter 0.4.2 to 0.4.3). Its commit `445647e` shows
  as verified, and the pull request job, under `block`, downloaded the artifact
  with `results-receiver` alone allowed.
- **Not taken:** pinact (v5.0.0), whose `pinact run --check` would add that each
  SHA is reachable from the tag its comment names, which rule 5 does not; and
  self-hosted Renovate (44.3.1 or later for CVE-2026-88884), a second bot and a
  config dialect for a roster the check already parses.

### 3.3 Immutable releases on every releasing target

- **What:** once on, a published release's tag and assets are locked and the
  release carries a Sigstore attestation, beside `protect-stable` and
  `.github/allowed_signers`. On in sharerr-rs and python-constricter since
  2026-10-31 and in say-hi and instadroid since 2026-11-08, as is the
  SHA-pinning requirement in every repository, both set by hand with the
  README's `gh api` calls; `immutable_releases = true` is in all four
  `repos/*.toml` (say-hi's and instadroid's not committed).
  `scripts/rulesets.sh diff` compares them
  when its token has Administration read, which the sync App lacks (granting it
  also needs `permission-administration: read` on `sync.yml`'s mint steps), so the
  weekly run names them as hidden.
- **say-hi, on `main` (`7e6daa3a0f0da589e24933b78e2c4a641df9dc33`):** `publish` creates a draft, attaches every asset and the
  package repository, then publishes with
  `gh release edit --draft=false`, in a step that runs whether the package
  repository attached or not. A new `demo` job renders the packages tape at the
  tag, so `demo.gif` goes on with the rest; `demos.yml`'s `attach` job is gone.
  `gh_asset.sh` reads the release id off the release list, since
  `releases/tags/<tag>` answers 404 for a draft.
- **instadroid, on `main` (#117):** `publish.yml`'s
  `release` job creates a draft, uploads the deploy bundle, then publishes; a
  re-run against a published release edits only its notes.
- **Left for both:** read each one's next tag run, the first to publish
  under the setting (a prerelease tag is the cheapest proof).
- **No releases:** homebrew-tap and ci-shared publish none, so the setting has
  nothing to lock there.

### 3.4 A shared push ruleset

Rulesets of type `push` apply to every branch and can refuse paths
(`*.key`, `*.pem`, `.env`, `secrets/`) and files over a size. One
`rulesets/push.json` rendered and diffed like the other three would make the
`.gitignore` secret patterns a server-side rule. Low value for one
maintainer whose `gitleaks` check runs on every push; worth it only if a
target gains contributors.

### 3.5 jactionlint in place of actionlint (_batch_, decided against for now)

- **What:** [jdx/jactionlint](https://github.com/jdx/jactionlint), an
  MIT-licensed fork of actionlint that accepts `uses: $/...`, which would
  unblock 1.1. Not taken: the first release was 2026-10-05, it reached v2.3.0
  within three weeks with a major bump four days in (v2.4.0 on 2026-10-29), and
  it has one maintainer. Revisit once it has a settled release history, or drop
  it if actionlint accepts `$/` first.
- **Tried (v2.3.0, on a copy of the tree with every local `uses:` rewritten
  to `$/`):** `--profile=correctness` is clean where actionlint 1.7.12 fails
  every `$/` line; it reads a `$/` action's `action.yml`, so an unknown or
  missing input fails as it does for `./`. Its `self-repository` rule, with a
  `--fix=unsafe` rewrite, matches zizmor's. The default profile finds nothing
  new on this repository's workflows; `pedantic` adds 34 (`require-shell`
  17, `require-expression-wrapping` 10).
- **What the swap would take:**
  - Long options only: `-config-file` and `-oneline` are refused, so
    `scripts/check.sh` and `tests/check_test.sh` change. It runs only inside
    a git repository.
  - It reads `.github/actionlint.yaml` but applies its larger `default`
    profile unless the file sets `profile: correctness`; pin that to keep
    today's checks across its fast releases.
  - Linting `files/` here: a `$/` action and a `workflow_run` workflow name
    resolve against this repository's root, so `advisory-note`,
    `fetch-latest-artifact` and pages.yml's `Coverage` trigger are reported
    missing. Lint the renderings in a scratch git tree shaped like a target,
    or ignore `invalid-local-action` and `workflow-run-names` there.
  - A `tools.txt` row: its archives follow actionlint's naming
    (`jactionlint_%v_linux_amd64.tar.gz`) with a checksums file and a
    Sigstore bundle.
  - sharerr-rs's required check `workflow lint (zizmor + actionlint)` is
    renamed in its ruleset by hand if the job name changes.
- **Not evaluated:** it claims a rule for every zizmor 1.30.1 audit (zizmor is
  pinned at 1.31.1 since), which could later replace zizmor as well.

## 4. More files into `files/`

From `scripts/near_census.py --normalize` over the sibling checkouts. The
template engine's `shared:if repo=<name>` blocks already carry per-target
rows in `dependabot.yml` and `tools.txt`, so a file that is mostly common
with a per-repository tail is a template, not a per-repository file.

| Path                    | Held by                     | Alike                         | Call                                   |
| ----------------------- | --------------------------- | ----------------------------- | -------------------------------------- |
| `.prettierignore`       | 4 repos, 6 to 8 lines       | differ by build dirs          | leave                                  |
| `.typos.toml`           | 4 repos, 14 to 50 lines     | a common head, per-repo words | leave                                  |
| `.hadolint.yaml`        | say-hi, sharerr-rs (34, 29) | instadroid's is 3 lines       | leave                                  |
| `.tool-versions`        | 3 repos, 2 to 4 lines       | different tools               | leave                                  |
| `docs/GOVERNANCE.md`    | 3 repos, 51 to 82 lines     | ratio 0.24 to 0.27            | leave, or template its policy sections |
| `.claude/settings.json` | 3 repos                     | differ                        | leave: project settings                |

`bug_report.yml` and `feature_request.yml` stay per-repository by decision. So do
`.prettierignore`, `.typos.toml` and `.hadolint.yaml`: they share a line or two,
and a template would be mostly per-repository blocks.

## 5. Known issues

### 5.1 harden-runner `block` drops allowlisted hosts on some westus2 runners

- **What:** GitHub runs an experiment on some westus2 hosted runners that adds
  its own DNS resolver (`egress-dns-resolver.service`, on `127.0.0.100:53`).
  On those runners harden-runner's Community-tier agent sees the DNS queries
  but not the answers, so it never maps an allowlisted host to its IP and
  drops the connection. Here it fails `checks.yml` at zizmor's
  `known-vulnerable-actions` audit: `api.github.com` resolves to
  `20.29.134.x`, the connection is dropped, and zizmor reports
  `error sending request for url (https://api.github.com/advisories?...)`.
  Seen on `ubuntu-26.04` image `20261012.163.1` (runs 39797240128 and
  39828192413); any repository with a `block` job is exposed.
- **Also at `actions/download-artifact`:** python-constricter's own
  `build.yml` lost a `Compiled wheel` job to it twice, a second after
  harden-runner engaged, both on westus2: the step fails with
  `ECONNREFUSED` from `ListArtifacts`, and the post step shows a GitHub IP
  (`140.82.11x.22:443`) dropped with an empty `domain:`. Seen on
  `ubuntu-24.04-arm` (run 40057157703, 2026-10-24) and on `ubuntu-26.04`
  image `20261012.163.1` (run 40216058251 attempt 2, 2026-10-25). The second
  job stayed `in_progress` after its post steps ended, so the run never
  completed and took `gh run cancel` before `gh run rerun --failed`. A retry
  of the download step there would ride it out.
- **Measured, 2026-10-24 to 10-31,** with a one-off script over the runner region
  in each job's log, across sharerr-rs, instadroid, homebrew-tap and saffron. Of
  the 10 jobs that hit a
  limit, the 9 whose logs remain all ran `block` on westus2; a sample of 400
  passing jobs held no `block` job on westus2, 20 `audit` jobs on westus2, and 77
  `block` jobs elsewhere. In one stuck job's post step, the runner's own
  connection (`Runner.Worker`) is dropped too, which is why a job stays open after
  its last step.
- **Upstream:** harden-runner v2.22.3 (2026-10-27), pinned everywhere since
  2026-11-06, fixes "unexpected blocking of allowed connections caused by
  GitHub's DNS resolver and outbound proxy experiment on GitHub-hosted Linux
  runners". v2.22.4 (2026-11-06, inside the cooldown) enables that workaround by
  default when its feature flags cannot be fetched, which suggests v2.22.3 gates
  it on a flag fetched at start; it clears the cooldown on 2026-11-13.
  [actions/runner-images#14925](https://github.com/actions/runner-images/issues/14925)
  was closed as completed on 2026-11-06, with no comment from GitHub on the
  DNS-observation part.
  [step-security/harden-runner#705](https://github.com/step-security/harden-runner/issues/705)
  covers the earlier port conflict on `127.0.0.1:53`, fixed. Checked 2026-11-07.
- **Until then:** jobs with no write token run `audit` (`release-note.yml`,
  `pages.yml`'s build). Jobs that keep `block` start with a `dns-experiment` step
  that refuses the runner when `egress-dns-resolver.service` is active, before the
  agent engages, so they fail in seconds; `rerun-timeouts.yml` reruns that failure.
  `scorecard.yml` has no such step, since its publish check restricts the job's
  steps, so it can still stick. Neither has been seen on a runner in the experiment:
  the first refusal, or a stuck `block` job with the step, is the check. A stopgap
  not taken: retry zizmor with `--offline` when its online audit cannot reach
  GitHub (skips `known-vulnerable-actions` on that run).
- **Recognize it:** `Region: westus2` in the job's set-up log, and in
  harden-runner's post step every `endpoint called` line has an empty
  `domain:`, with `ip address dropped` for an allowlisted host's IP.
- **Close it:** the `dns-experiment` step refuses an experiment runner before
  harden-runner engages, so no run can show v2.22.3's fix while it is there.
  Drop it from one `block` job and read that job's runs until one lands on
  westus2 with `egress-dns-resolver.service` active; once one passes, drop the
  step everywhere and move `release-note.yml` and `pages.yml`'s build back to
  `block`, or take v2.22.4 on 2026-11-13 and do the same.

### 5.2 shfmt and `brew style` disagree on homebrew-tap's shell layout

- **What:** homebrew-tap's `brew style` runs Homebrew's shfmt wrapper over
  every `*.sh` in the tap, which wants `then` and `do` on their own line and
  `case` items indented. Plain shfmt with the shared `.editorconfig` (an
  editor's format-on-save, a format-on-write hook) rewrites both back, so
  `docs/tapes/fixtures.sh` fails `brew style` after any such save. No
  EditorConfig key gives Homebrew's `do` placement.
- **Done:** a `shared:if repo=homebrew-tap` block in `files/.editorconfig`,
  merged in homebrew-tap, sets `ignore = true` for `[docs/tapes/*.sh]`, so
  `shfmt -l` over its tree skips `fixtures.sh` and `brew style` alone owns that
  layout.
- **Left:** shfmt 3.14.1 honors `ignore` only when it walks a directory
  (`shfmt -d <file>` still reformats it), so whatever formats one file on
  save must also skip a file `shfmt -f <dir>` leaves out. Until it does,
  apply `brew style --fix`'s diff by hand and do not reformat afterwards.

### 5.3 Jobs that time out without doing the work

- **What:** `scripts/retried_timeouts.py` found 105 jobs since 2026-08-01 that
  hit a time limit and passed within two retries, nearly all from 2026-10-21 on
  `ubuntu-26.04`. Its outcome column shows most never ran to their limit: 58
  ended their `Complete job` step yet stayed open, 40 recorded no finished step.
  A larger limit does not help them, nor a smaller one: `rerun-timeouts.yml`'s
  5-minute job stayed open 10. Item 5.1 is the cause wherever a log remains, by its
  measurement above.
- **Done:** `rerun-timeouts.yml` reruns a run's failed jobs when one hit a time
  limit, at most twice, under `block` since it holds a write token; item 5.1 can
  fail it, which leaves that run for a rerun by hand. Limits were lowered from
  `scripts/job_durations.py`'s 20 newest passing runs: 5 minutes under a 1-minute
  longest run, else 1.5 times the longest rounded up to 5 with a floor of 10, and
  15 to 20 for jobs that compile or build an image, whose cold runs the sample may
  miss. Release and publish jobs and jobs seen under 5 times keep theirs.
- **Not done:** reporting the jobs that finished yet stayed open to GitHub. A move
  back to `ubuntu-24.04` no longer tests anything: 5.1's measurement separates
  `block` from `audit` on the one image.
- **Verify:** after the first automatic rerun of a `CI` run on `main`, that the
  workflows chained off `CI` fired from attempt 2, since a rerun started by
  `GITHUB_TOKEN` may not emit `workflow_run`. From 2026-11-08, a week after the
  limits' sync merged, rerun the scan; a job killed by a new limit shows as
  `stopped` with active minutes near its limit.

### 5.4 Sync pull requests still run sharerr-rs's `CodeQL (rust)`

- **What:** 135 of its 682 runner minutes in the week measured, and 34% of its
  minutes were `ci-sync`'s. Its other Rust
  jobs and both Docker builds now skip a pull request that touches only shared
  CI files. This one is the shared `codeql.yml`, whose header says a skipped
  category leaves code scanning waiting on a result, and code scanning is in
  that repository's ruleset.
- **Still runs:** 7m40s on sync pull request 153 (2026-11-02), where every other
  Rust and Docker job skipped.
- **Verify first:** whether a skipped `CodeQL (rust)` holds a sync pull request's
  merge. Needs a real pull request; nothing local shows it.

## 6. Simplifications

The review's 22 items are done. What they left in force:

- A label is created only with an issue, so a color or description changed in a
  workflow reaches GitHub only with the next new issue.
- `fetch-latest-artifact`'s `artifact-name` is a name or a `{a,b}` list, the forms
  every caller uses; a wildcard no longer matches. `find_tree_run.sh` keeps its run
  lookups for the event and conclusion, which an artifact does not carry.
- `link-check.yml` keeps `upsert-tracking-issue`'s `body-file`, since lychee's
  report is Markdown.
- `lint_workflows.sh` rule 7 does not judge an indented `source` in a script: it is
  conditional, and `setup-tool`'s `install.sh` reaches its apt library only for
  some kinds. A sparse checkout of an action or of `trivy_scan.sh` lists `lib.sh`
  too.
- `scratch/README.md` is shared and skipped by homebrew-tap, which has no
  `scratch/`, and by python-constricter, since the sync would overwrite its own
  README and the per-script list in it; drop that skip to replace them.

## 7. To consider

Evaluated, not decided: nothing here is on the order of work until it is taken up.

### 7.1 `mise.toml` in place of `tools.txt` (_batch_, L)

- **What:** make `mise.toml` and `mise.lock` the one list of pinned CI tools, in
  place of `.github/actions/setup-tool/tools.txt`, its installer, and the
  `setup-tools` action. say-hi's `mise.toml` copies `tools.txt` today, with a
  drift check to hold the two together; a single list removes the copy.
- **What mise covers (2026.10.19):** `mise.lock` records versions, checksums and
  download URLs per platform, and `--locked` stops an install calling the GitHub
  or aqua registry APIs for a URL. `mise lock --bump --dry-run --json` lists
  updates without writing, and `minimum_release_age` is the cooldown.
- **What blocks a full swap:** `mandoc` and `checkbashisms` are not in
  mise's registry, and `mandoc` builds from source. Each takes apt, at
  a floating version, or a small kept installer; apt unless the exact version
  matters.
- **Verify first:** `cargo-mutants` and `cargo-semver-checks` are not in the
  registry either and need another backend. `minimum_release_age` skips exact
  versions, so how it combines with `--bump` on exact pins is untested, as is
  `mise lock` on a target.
- **Cost:** every job that needs a tool installs mise, through one more pinned
  action or a download, and each harden-runner allow list gains mise's hosts.
  `check_tool_versions.sh`, `scripts/apply_bumps.sh` and say-hi's `tools_test.sh`
  and `drift_test.sh` are rewritten. Every target using `setup-tools` needs a
  `mise.toml`.
- **How, if taken up:** try say-hi's
  `quick lint` job first, the cheapest way to measure what mise adds to a job's
  time and find the hosts it needs, then move every target as one batch.
