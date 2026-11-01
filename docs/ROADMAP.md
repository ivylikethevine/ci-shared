# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone.

## Order of work

Ranked by value for size; the numbers are the items below. S, M and L are sizes.

1. 3.2's first run that finds a bump, the weekly one from 2026-11-02 at 07:53
   UTC (S).
2. 3.1, read the first weekly run under the App, 2026-11-02 at 14:41 UTC (S).
3. 5.3's and 5.4's checks, each on the next run that shows it (S).
4. 3.4, say-hi's and instadroid's release workflows (M).
5. The batch when it is started, say-hi first: 1.4 (S), 1.3 (S), 1.2 (M, one
   session per repository).

Waiting on upstream: 1.1, 3.6, 5.1, 5.2. Not worth doing as things stand: 3.5.

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
  now (3.6). Not evaluated: the fork `kjanat/actionlint`, which says it is a
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

### 1.3 The targets' own action SHAs (_batch_)

- **Override:** markdownlint 0.42.0, which markdownlint-cli2 0.24.0 pulls in, pins
  `re2js` 2.8.6 under GHSA-gg6h-894w-4m9c, fixed in 2.8.7. `overrides` holds
  `re2js` at 2.9.0, the newest past the cooldown; drop it once markdownlint's
  own pin passes the advisory.
- **Left:** the targets' own workflows keep the old action SHAs until each moves
  them, as its own `tool-versions` issue will say. In the batch, say-hi goes
  first.

### 1.4 Drop `setup-tool`'s `version` and `sha256` inputs (_batch_)

No target's workflow passes them, and the drift check reads `tools.txt` directly,
so the inputs, their refusal logic in `install.sh` and the cases pinning them go
together; `setup-tool` then reads the row's pin and sha256 alone. About 20 lines,
and say-hi's `tests/packaging/packaging_ci_workflows_test.sh` loses its override
cases in the same pass.

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

- **Done ahead of it:** kcov 43 builds under cmake 4.4 and gcc 16, newer
  than the image's; `apt/lib.sh` now drops vendor `*.sources` files as well
  as `*.list`, so a deb822 vendor repository on 26.04 cannot fail
  `apt-get update`; `setup-tool`'s cache keys carry the image name
  (`ImageOS`), so a kcov built on 24.04 is not restored on 26.04 against
  libraries it was not linked to; `checks.yml` takes a `runner` input on
  dispatch.
- **Run:** `checks.yml` on `ubuntu-26.04` (run 39189568504): both jobs
  green, kcov 43 built from source in under a minute on a cold cache keyed
  `ubuntu26`, the checks and the 100% coverage gate as on 24.04.
- **Since:** this repository's `CI`, `CodeQL`, `Link check`, `Scorecard` and
  `Sync` pass on `ubuntu-26.04` (2026-10-24), and `tool-versions.yml` does too
  (run 40754857850, 2026-10-28). say-hi's renamed suite jobs are on its `main`,
  and its live `main` ruleset requires them. instadroid's own jobs name
  `ubuntu-26.04`, and its `main` CI passes on them (run 41258224153, 2026-10-31).
- **kcov:** 26.04 packages kcov `43+dfsg-2`, which records no hit on a
  multi-line array assignment; this repository's coverage job and say-hi's
  build upstream kcov 43 from `tools.txt`'s `cmake` row instead.
- **Still exposed:** `checks.yml` and `coverage` build their venv on the
  system python3 (3.14: fine for constricter's `min-python = "3.11"` and
  coverage 7.17); `image-scan.yml` meets docker 29.

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
- **Left:** the `sync-health` issue (#4) is still open from the 2026-10-26
  weekly run, the last under the PATs, naming drift and rulesets. The
  2026-11-02 run is the first under the App, and closes it if every check
  passes.
- **Still by hand per target:** a mint step and a `TOKEN_<NAME>` line in
  `sync.yml`, which `scripts/check.sh` now fails without.

### 3.2 Bumps as a pull request, not a hand edit

- **Done in the tree:** `.github/workflows/bump-tools.yml`, weekly after the
  version check. `check_tool_versions.sh` stays read-only and lists what is behind
  in `CI_FIX_LIST`; `scripts/apply_bumps.sh` edits it, in this repository alone
  since the sync owns the targets' copies and only this repository's manifest
  kinds are handled: `tools.txt` rows with each asset's sha256, every `uses:`, the
  inline pin, the npm manifest and lock, and the `.in` files and their locks.
  `scripts/bump_pr.sh` writes one draft pull request on `tool-bumps`, in a job of
  its own holding the App's token; a commit naming no author is signed by GitHub
  for the App, so it needs no SSH key and keeps file modes.
- **Run:** the scripts on a copy of the tree with no cooldown moved
  `step-security/harden-runner`, python-constricter and reuse and recompiled the
  dev lock. Not run on GitHub: nothing here has minted the token or written a
  commit.
- **Left:** the App is on this repository. The first dispatch (run 41261382260,
  2026-10-31) passed with nothing to bump, so its pull request job was skipped and
  neither point below has been tested. On the first run that finds a bump, check
  that the commit shows as verified, and that block lets the
  artifact upload through with `results-receiver` alone allowed, as the targets'
  jobs do.
- **Not taken:** pinact (v5.0.0), whose `pinact run --check` would add that each
  SHA is reachable from the tag its comment names, which rule 5 does not; and
  self-hosted Renovate (44.3.1 or later for CVE-2026-88884), a second bot and a
  config dialect for a roster the check already parses.

### 3.4 Immutable releases on the other releasing targets

- **What:** once on, a published release's tag and assets are locked and the
  release carries a Sigstore attestation, beside `protect-stable` and
  `.github/allowed_signers`. On in sharerr-rs and python-constricter since
  2026-10-31, as is the SHA-pinning requirement in every repository, both set by
  hand with the README's `gh api` calls. `scripts/rulesets.sh diff` compares them
  when its token has Administration read, which the sync App lacks (granting it
  also needs `permission-administration: read` on `sync.yml`'s mint steps), so the
  weekly run names them as hidden.
- **Left:** say-hi and instadroid cannot take it yet: each publishes its
  release before attaching assets (say-hi's `_ci_upload_assets` and package
  repository after `gh release create`; instadroid's
  `gh release upload --clobber`), which a locked release refuses. Each needs
  its release created with `--draft`, its assets attached, then
  `gh release edit --draft=false`, in its own workflow, before its
  `immutable_releases` turns on.

### 3.5 A shared push ruleset

Rulesets of type `push` apply to every branch and can refuse paths
(`*.key`, `*.pem`, `.env`, `secrets/`) and files over a size. One
`rulesets/push.json` rendered and diffed like the other three would make the
`.gitignore` secret patterns a server-side rule. Low value for one
maintainer whose `gitleaks` check runs on every push; worth it only if a
target gains contributors.

### 3.6 jactionlint in place of actionlint (_batch_, decided against for now)

- **What:** [jdx/jactionlint](https://github.com/jdx/jactionlint), an
  MIT-licensed fork of actionlint that accepts `uses: $/...`, which would
  unblock 1.1. Not taken: the first release was 2026-10-05, it reached v2.3.0
  within three weeks with a major bump four days in, and it has one
  maintainer. Revisit once it has a settled release history, or drop it if
  actionlint accepts `$/` first.
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
- **Measured, 2026-10-24 to 10-31:** `scratch/ci_census.py regions` over
  sharerr-rs, instadroid, homebrew-tap and saffron. Of the 10 jobs that hit a
  limit, the 9 whose logs remain all ran `block` on westus2; a sample of 400
  passing jobs held no `block` job on westus2, 20 `audit` jobs on westus2, and 77
  `block` jobs elsewhere. In one stuck job's post step, the runner's own
  connection (`Runner.Worker`) is dropped too, which is why a job stays open after
  its last step.
- **Upstream:**
  [actions/runner-images#14925](https://github.com/actions/runner-images/issues/14925)
  is open, last updated 2026-10-19, with no answer from GitHub on the
  DNS-observation part.
  [step-security/harden-runner#705](https://github.com/step-security/harden-runner/issues/705)
  covers the earlier port conflict on `127.0.0.1:53`, fixed. harden-runner
  v2.22.2 changes DNS tracing for the Enterprise tier only.
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
  `domain:`, with `ip address dropped` for an allowlisted host's IP. Close
  this once #14925 reports a fix and a westus2 run passes.

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
  `GITHUB_TOKEN` may not emit `workflow_run`. A week after the sync merges, rerun
  the scan; a job killed by a new limit shows as `stopped` with active minutes
  near its limit.

### 5.4 Sync pull requests still run sharerr-rs's `CodeQL (rust)`

- **What:** 135 of its 682 runner minutes in the week measured
  (`scratch/ci_census.py`), and 34% of its minutes were `ci-sync`'s. Its other Rust
  jobs and both Docker builds now skip a pull request that touches only shared
  CI files. This one is the shared `codeql.yml`, whose header says a skipped
  category leaves code scanning waiting on a result, and code scanning is in
  that repository's ruleset.
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
  place of `.github/actions/setup-tool/tools.txt` and the `setup-tool` and
  `setup-tools` actions. say-hi's `mise.toml` copies `tools.txt` today, with a
  drift check to hold the two together; a single list removes the copy.
- **What mise covers (2026.10.19):** `mise.lock` records versions, checksums and
  download URLs per platform, and `--locked` stops an install calling the GitHub
  or aqua registry APIs for a URL. `mise lock --bump --dry-run --json` lists
  updates without writing, and `minimum_release_age` is the cooldown.
- **What blocks a full swap:** `kcov`, `mandoc` and `checkbashisms` are not in
  mise's registry, and `kcov` and `mandoc` build from source. Each takes apt, at
  a floating version, or a small kept installer; apt unless the exact version
  matters.
- **Verify first:** `cargo-mutants` and `cargo-semver-checks` are not in the
  registry either and need another backend. `minimum_release_age` skips exact
  versions, so how it combines with `--bump` on exact pins is untested, as is
  `mise lock` on a target.
- **Cost:** every job that needs a tool installs mise, through one more pinned
  action or a download, and each harden-runner allow list gains mise's hosts.
  `check_tool_versions.sh`, `scripts/apply_bumps.sh` and say-hi's `tools_test.sh`
  and `drift_test.sh` are rewritten. Every target using `setup-tool` needs a
  `mise.toml`.
- **How, if taken up:** try say-hi's
  `quick lint` job first, the cheapest way to measure what mise adds to a job's
  time and find the hosts it needs, then move every target as one batch.
