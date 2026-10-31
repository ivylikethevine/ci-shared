# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone.

## Order of work

Ranked by value for size; the numbers are the items below. S, M and L are sizes.

1. 3.1, read the first weekly run under the App on 2026-11-02 (S).
2. 5.3, test `ubuntu-24.04` on one repository and read the scan after (S).
3. 6.1 item 5, the check on `sync.yml`'s mint steps (S).
4. 6.2 item 21, `lint_workflows.sh` reading `source` lines (M): a miss only
   fails at release.
5. 3.3 and 3.4, the settings to switch on by hand (S).
6. 3.2, bumps as a pull request (L), which also shortens 1.3.
7. The batch when it is started: 1.3 (S), 1.2 (M, one session per repository).
8. The remaining S items: 6.1 item 7, 6.2 items 12, 17, 19 and 20.
9. 6.2's M items: 10, 15 and 16.
10. Section 4's templates (M).

Waiting on upstream: 1.1, 3.6, 5.1, 5.2. Not worth doing as things stand: 3.5.

## 1. Fixes in this repository

### 1.1 The `$/` rewrite and zizmor `self-repository` (_batch_)

- **What:** Scorecard v5.6.0, which `ossf/scorecard-action` v2.5.0 ships,
  reads `uses: $/...` as a local action, so the rewrite of every
  `uses: ./.github/...` to `$/.github/...` and `self-repository` back on in
  `.github/zizmor.yml` could follow. Blocked: actionlint 1.7.12, the newest,
  rejects `$/` ("ref is missing"), and no actionlint issue or pull request
  tracks it. Every repository's lint gate runs actionlint. jactionlint
  accepts it but is not taken for now (3.6).
- **How, once actionlint accepts it:** rewrite the shared workflows and each
  target's own, extend `lint_workflows.sh` rule 7 to `$/` (it checks the
  sparse-checkout list for `./` refs only), re-enable the rule, and update
  each target's disabled-rules note.

### 1.2 harden-runner `block` on macOS and Windows jobs (_batch_)

- **What:** harden-runner v2.20.0 supports `egress-policy: block` on GitHub's
  macOS and Windows runners in the free tier, so those jobs can move from
  `audit`. A weekly external-link check stays `audit`, and Windows arm64 has no
  agent, so those legs stay unmonitored.
- **How:** `scratch/egress_census.sh` lists the jobs and
  `scratch/egress_baseline.sh` reads each job's endpoints from its audit runs
  for `allowed-endpoints`. The jobs live in the targets' own workflows, one
  session per repository; update each disabled-rules row that says only audit
  is supported.

### 1.3 The bumps the `tool-versions` issue lists (_batch_)

- **What:** issue #3 names each pin past the cooldown. As of its 2026-10-28 run:
  trivy, terraform, `github/codeql-action`, `step-security/harden-runner`,
  markdownlint-cli2 and python-constricter. actionlint 1.7.12 is still the
  newest, which keeps 1.1 blocked.

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
  and its live `main` ruleset requires them.
- **instadroid:** its own 21 `ubuntu-latest` jobs now name `ubuntu-26.04`; its
  next CI run on them is the check.
- **Not the image's:** the 2026-10-24 sync pull requests' CI failures were a
  new RustSec advisory in sharerr-rs's `cargo-deny`, `filelock` and `setuptools`
  advisories in instadroid's `pip-audit`, and in say-hi a `test_runner_ci`
  cost-table test and a harden-runner agent that exited when `cdn.dl.k8s.io` did
  not resolve. Those pull requests are closed; later syncs replaced them.
- **kcov:** 26.04 packages kcov `43+dfsg-2`, which records no hit on a
  multi-line array assignment; this repository's coverage job and say-hi's
  build upstream kcov 43 from `tools.txt`'s `cmake` row instead.
- **Still exposed:** `checks.yml` and `coverage` build their venv on the
  system python3 (3.14: fine for constricter's `min-python = "3.11"` and
  coverage 7.16); `image-scan.yml` meets docker 29.

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
  `sync.yml` (6.1 item 5).

### 3.2 Bumps as a pull request, not a hand edit

The weekly `tool-versions` issue already names every bump and, for action
SHAs, the commit to pin. Three ways to turn it into a pull request on this
repository, which the sync then carries everywhere:

- **In-house `--apply`** (recommended): `check_tool_versions.sh` gains a mode
  that edits what it reported: `tools.txt` rows (pin, then the sha256 by
  fetching the new asset for each platform the row names), the `-> @sha`
  lines across every `uses:`, `npm install --prefix .github <pkg>@<ver>`
  for the Markdown tools, `pip-compile --upgrade-package` for
  `requirements-dev.in` and `requirements-coverage.in`. A workflow runs it after the weekly check and opens
  one pull request. The sha256 recomputation is the one step no off-the-shelf
  tool does for this roster format.
- **pinact** (v5.0.0, 2026-09-12) for the action SHAs alone:
  `pinact run --update` rewrites `uses:` pins with their version comments and
  `pinact run --check` is a lint; it does not know `tools.txt` or the npm lock.
  If adopted, its check mode joins `check.sh` beside `lint_workflows.sh`: it also verifies
  that each SHA is reachable from the tag its comment names, which rule 5 does
  not.
- **Renovate**: self-hosted through
  `renovatebot/github-action` (v46.3.8), Renovate 44.3.1 or later
  (CVE-2026-88884), regex custom managers for `tools.txt` plus
  `postUpgradeTasks` for the sha256, `ignorePaths` for the root symlinks, its
  endpoints in harden-runner. A second bot and a config dialect for a roster
  the in-house script already parses.
- **Either way** the pull request edits `.github/workflows/`, which
  `GITHUB_TOKEN` may not push: the App of 3.1 (installed on this repository
  too) is the token.

### 3.3 "Require actions to be pinned to a full-length commit SHA" (by hand)

- **Left:** switch it on in every repository, this one included, with the
  README's `gh api -X PUT .../actions/permissions` (The rulesets). The field
  is `sha_pinning_required`; `scripts/rulesets.sh diff` compares it when its
  token has Administration read, which the sync App lacks (granting it also
  needs `permission-administration: read` on `sync.yml`'s mint steps), so the weekly run
  names it as hidden.

### 3.4 Immutable releases on the releasing targets (by hand)

- **What:** once on, a published release's tag and assets are locked and the
  release carries a Sigstore attestation, beside `protect-stable` and
  `.github/allowed_signers`. sharerr-rs and python-constricter set
  `immutable_releases = true`: sharerr-rs's release has no assets, and
  python-constricter's `gh release create TAG assets/*` keeps the release a
  draft until its uploads finish.
- **Left:** `gh api -X PUT repos/OWNER/REPO/immutable-releases` on those two
  by hand. say-hi and instadroid cannot take it yet: each publishes its
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

From `scratch/near_census.py --normalize` over the sibling checkouts. The
template engine's `shared:if repo=<name>` blocks already carry per-target
rows in `dependabot.yml` and `tools.txt`, so a file that is mostly common
with a per-repository tail is a template, not a per-repository file.

| Path                    | Held by                     | Alike                         | Call                                   |
| ----------------------- | --------------------------- | ----------------------------- | -------------------------------------- |
| `.prettierignore`       | 4 repos, 6 to 8 lines       | differ by build dirs          | template with repo blocks              |
| `.typos.toml`           | 4 repos, 14 to 50 lines     | a common head, per-repo words | template with repo blocks              |
| `.hadolint.yaml`        | say-hi, sharerr-rs (34, 29) | instadroid's is 3 lines       | template for the two                   |
| `.tool-versions`        | 3 repos, 2 to 4 lines       | different tools               | leave                                  |
| `docs/GOVERNANCE.md`    | 3 repos, 51 to 82 lines     | ratio 0.24 to 0.27            | leave, or template its policy sections |
| `.claude/settings.json` | 3 repos                     | differ                        | leave: project settings                |

`bug_report.yml` and `feature_request.yml` stay per-repository by decision.

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
- **Upstream:**
  [actions/runner-images#14925](https://github.com/actions/runner-images/issues/14925)
  is open, with no answer from GitHub on the DNS-observation part.
  [step-security/harden-runner#705](https://github.com/step-security/harden-runner/issues/705)
  covers the earlier port conflict on `127.0.0.1:53`, fixed. harden-runner
  v2.22.2 changes DNS tracing for the Enterprise tier only.
- **Until then:** rerun the job; a runner outside the experiment passes. Two
  stopgaps, not taken: retry zizmor with `--offline` when its online audit
  cannot reach GitHub (skips `known-vulnerable-actions` on that run), or
  `egress-policy: audit` (_batch_).
- **Recognize it:** `Region: westus2` in the job's set-up log, and in
  harden-runner's post step every `endpoint called` line has an empty
  `domain:`, with `ip address dropped` for an allowlisted host's IP. Close
  this once #14925 reports a fix and a westus2 run passes.

### 5.2 shfmt and `brew style` disagree on homebrew-tap's shell layout

- **What:** homebrew-tap's `brew style` runs Homebrew's shfmt wrapper over
  every `*.sh` in the tap, which wants `then` and `do` on their own line and
  `case` items indented. Plain shfmt with the shared `.editorconfig` (an
  editor's format-on-save, a format-on-write hook) rewrites both back, so
  `docs/demo/fixtures.sh` fails `brew style` after any such save. No
  EditorConfig key gives Homebrew's `do` placement.
- **Done:** a `shared:if repo=homebrew-tap` block in `files/.editorconfig`,
  merged in homebrew-tap, sets `ignore = true` for `[docs/demo/*.sh]`, so
  `shfmt -l` over its tree skips `fixtures.sh` and `brew style` alone owns that
  layout.
- **Left:** shfmt 3.14.1 honors `ignore` only when it walks a directory
  (`shfmt -d <file>` still reformats it), so whatever formats one file on
  save must also skip a file `shfmt -f <dir>` leaves out. Until it does,
  apply `brew style --fix`'s diff by hand and do not reformat afterwards.

### 5.3 Jobs that time out without doing the work

- **What:** `scratch/retried_timeouts.py` found 105 jobs since 2026-08-01 that
  hit a time limit and passed within two retries, nearly all from 2026-10-21 on
  `ubuntu-26.04`. Its outcome column shows most never ran to their limit: 58
  ended their `Complete job` step yet stayed open, 40 recorded no finished step.
  A larger limit does not help them. Item 5.1 is the likely cause of many,
  unconfirmed: one job's log was read, a westus2 checkout refused 5 ms after
  harden-runner engaged, with `github.com` on its allowed list.
- **Done:** `rerun-timeouts.yml` reruns a run's failed jobs when one hit a time
  limit, at most twice, under `block` since it holds a write token; item 5.1 can
  fail it, which leaves that run for a rerun by hand. Limits were lowered from `scratch/job_durations.py`'s 20 newest passing
  runs: 5 minutes under a 1-minute longest run, else 1.5 times the longest
  rounded up to 5 with a floor of 10, and 15 to 20 for jobs that compile or build
  an image, whose cold runs the sample may miss. Release and publish jobs and
  jobs seen under 5 times keep theirs.
- **Not done:** moving one repository back to `ubuntu-24.04` to test the image,
  comparing `block` with `audit`, and reporting the jobs that finished yet stayed
  open to GitHub.
- **Verify:** after the first automatic rerun of a `CI` run on `main`, that the
  workflows chained off `CI` fired from attempt 2, since a rerun started by
  `GITHUB_TOKEN` may not emit `workflow_run`. A week after the sync merges, rerun
  the scan; a job killed by a new limit shows as `stopped` with active minutes
  near its limit.

## 6. Simplifications

From a review of the whole tree for reuse, simplification, efficiency and
fixes at the right depth. Each item is S, M or L in size; **(behaviour)**
marks one that changes what runs.

### 6.1 This repository's own CI and configuration

- **1. A coverage-only lock**: done: `requirements-coverage.in`, pulled into
  `requirements-dev.in` with `-r`, and installed alone by the coverage job.
- **2. kcov from `setup-tools`**: done; the one-line array rule is gone.
- **3. A shared base file list**: done: `repos/_base.toml`, `base = true`,
  `skip`.
- **4. Repository-wide template values**: done: a target's `[values]`.
- **5. Check `sync.yml`'s mint steps** (S): each target's mint step and
  `TOKEN_<NAME>` line are listed by hand; a `check.sh` assertion against the
  entries' `token_secret` catches a missing one before a run does.
- **6. `REUSE.toml` as an own file**: done. This repository's copy drops the
  code-of-conduct annotation, which `files/REUSE.toml`, read as a nested
  REUSE.toml, already makes for `files/docs/`.
- **7. Directory symlinks for `setup-tool` and `setup-tools`** (S): per-file
  symlinks mean a new file in either action needs a link by hand.
- **8. One runner default in `checks.yml`**: done.
- **9. Target names in `scratch/near_census.py`**: done: built from the
  `repos/*.toml` stems, with the short forms in `SPELLINGS`.

### 6.2 Shared files

- **10. One workflow-command escaper** (M): `check_tool_versions.sh`,
  `upsert-tracking-issue`, `advisory-note` and `fetch-latest-artifact` each
  escape `%`, CR, LF and title separators. `lib.sh` is the place: the sparse
  checkout in image-scan's scan job now lists it, but any other sparse checkout
  of these actions must too (item 21).
- **11. One set of trivy flags**: done: `_CI_TRIVY_FLAGS` in `lib.sh`, so a
  sparse checkout of `trivy_scan.sh` lists `lib.sh` too. sharerr-rs's own
  `docker.yml` has one, so its edit lands before the sync pull request that
  carries this.
- **12. Label created only with an issue** (S, behaviour):
  `upsert-tracking-issue` runs `gh label create --force` on every call.
  Check first that listing by a missing label returns empty, not an error.
- **13. No skip in `setup-tools/install-missing.sh`**: done; a cache miss
  installs every tool from its pin, as `setup-tool` does.
- **14. Image references read once**: done: `_ci_refs_pinned` filters the one
  read.
- **15. Report sections in `upsert-tracking-issue`** (M): `tool-versions.yml`
  and `link-check.yml` compose the issue body by hand, and tool-versions'
  plain fence breaks on backticks. `preamble` and `report-file` inputs reuse
  `advisory-note`'s fence.
- **16. One search for the latest run holding an artifact** (M):
  `fetch-latest-artifact` makes up to 20 calls one after another and
  `find_tree_run.sh` searches another way; one artifacts listing intersected
  with the run list is two calls.
- **17. `npm audit` once** (S): `advisories.yml` runs it again only to print a
  table of the JSON it holds.
- **18. `install.sh` branches**: done: one `tar -xf` for the tar kinds (a zip
  still takes `unzip`), and one "no binary" check after the `case`.
- **19. `_ci_files` in `_ci_extract`** (S, behaviour): `compgen -G` and git
  pathspecs give roster and image globs different meanings; check each
  target's roster globs first.
- **20. `release_notes.sh`'s `section()`** (S): one `awk` in place of a
  five-process pipeline, which also drops its SIGPIPE caveats.
- **21. `lint_workflows.sh` reads `source` lines** (M): rule 7 checks a sparse
  checkout's list for `./` refs only, so a listed script that sources a file
  left off the list passes every lint and fails when the job runs. Item 11 needed
  that line added by hand in sharerr-rs's `docker.yml`, whose scan runs only at
  release.
