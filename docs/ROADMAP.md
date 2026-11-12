# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone. A
finished item moves to [CHANGELOG.md](CHANGELOG.md).

## Order of work

Ranked by value for size. Items are numbered through the file; a letter marks
one step of an item. S, M and L are sizes.

- 10a, a passing `Sync` run that carries the `dns experiment` notice, under
  v2.22.3, or v2.22.4 from 2026-11-13; then 10b, the `dns-experiment` step's
  removal (S).
- Item 11's check, which needs a real pull request (S).
- Item 2, a `build.yml` dispatch on python-constricter's branch before it
  reaches `main` (S).
- Item 3, `rerun-timeouts.yml`, after 10b (S).
- 9b, the first automatic rerun on `main`, on the next run that shows it (S);
  it lapses once item 3 removes the workflow that reruns.

Waiting on upstream: items 4 and 6 (an actionlint release), 5 (a
markdownlint-cli2 release), 7 (jactionlint's release history) and 12 (shfmt's
`ignore` on a single file). Not worth doing as things stand: item 8.

## Fixes in this repository

### 2. harden-runner `block` on macOS and Windows jobs (_batch_, S)

- **What:** harden-runner v2.20.0 supports `egress-policy: block` on GitHub's
  macOS and Windows runners in the free tier, so those jobs can move from
  `audit`. A weekly external-link check stays `audit`, and Windows arm64 has no
  agent, so those legs stay unmonitored.
- **How:** `scripts/egress_census.sh` lists the jobs and
  `scripts/egress_baseline.sh` reads each job's endpoints from its audit runs
  for `allowed-endpoints`. The jobs live in the targets' own workflows, one
  session per repository; update each disabled-rules row that says only audit
  is supported.
- **say-hi:** `test-macos`, `windows-client.yml`'s x64 legs and
  `windows-e2e.yml`'s OpenSSH job pass under `block` (pull request run
  42959387908; the Windows jobs again on `main`, run 42961496714).
  `windows-e2e.yml`'s WSL job is back on `audit`: under `block` the
  distribution's connections hang even to an allowed host, so setup-wsl timed
  out (run 42940405659). `release.yml`'s `brew` stays `audit`: it runs only on
  a tag push, so its first `block` run would be a release, with `tap` waiting
  on it.
- **homebrew-tap:** the macOS leg of `ci.yml`'s `test` passes under `block` on
  `main` (run 42941662948), through a `runner.os` expression, from 13 audited
  runs that agree on seven hosts; its Linux leg stays `audit`.
- **python-constricter:** `ci.yml`'s `test` and `compiled` pass under `block`
  on every leg (pull request run 42942084798): their macOS legs reached nothing
  the Linux lists lacked, and the Windows legs add two certificate-revocation
  hosts. `build.yml`'s `compiled` is on `block` on every leg in its working
  tree, unproven: `egress_baseline.sh` over `release.yml` held endpoint data
  for 3 of the last 5 release runs, which agree on the Linux list plus
  `release-assets.githubusercontent.com`, two NuGet hosts on Windows and three
  certificate-revocation hosts there.
- **Left:** a `build.yml` dispatch on python-constricter's branch, before that
  branch reaches `main`: it publishes nothing, and a tag is otherwise the
  list's first `block` run. say-hi's `brew` has no run outside a release and
  its WSL job hangs under `block`, so both stay `audit`. sharerr-rs and
  instadroid have no macOS or Windows job.
- **For the next target:** the baseline held endpoint data for 3 of `ci.yml`'s
  last 10 passing runs, so a host only a cold cache fetches is in none of them;
  read the action's source for it (setup-wsl downloads its distribution from
  `releases.ubuntu.com`). The Windows agent names a WSL distribution's apt
  mirrors on 443 where apt's stock sources are http, so list both ports.
  harden-runner's README still says Windows and macOS are audit only, against
  v2.20.0's release note and the action's source, which hands `block` and the
  list to both agents.

### 3. Drop `rerun-timeouts.yml` (_batch_, S)

- **What:** a shared workflow that works around runner behaviour rather than
  fixing anything in a target: it retries a run whose job hit a time limit,
  where the rule in every target is to fix a slow job in code. It also reruns
  item 10's stuck jobs and the `dns-experiment` refusal, so it goes once item
  10 closes and that step is gone. `cancel-closed-pr.yml`, its pair in this
  item, is gone from `files/` and every target.
- **How:** remove it from `files/` and `repos/_base.toml`, each target's
  `[templates."rerun-timeouts.yml"]` table, `scripts/own_files.sh`'s row and
  this repository's own copy; update `tests/lib.sh`,
  `tests/own_files_test.sh`, `tests/check_test.sh`, README's workflow list and
  USAGE.md. The sync never deletes a file, so each target deletes its copy by
  hand in the batch, and say-hi's CONTRIBUTING.md drops its line.
- **Verified:** 9a's rescan found no job the lowered limits killed while
  doing its work; every retried job but one was item 10's stuck kind, and that
  one was a hung Docker Hub pull.

### 4. The `$/` rewrite and zizmor `self-repository` (_batch_)

- **What:** Scorecard v5.6.0, which `ossf/scorecard-action` v2.5.0 ships,
  reads `uses: $/...` as a local action, so the rewrite of every
  `uses: ./.github/...` to `$/.github/...` and `self-repository` back on in
  `.github/zizmor.yml` could follow. Blocked: actionlint 1.7.12, the newest,
  rejects `$/` ("ref is missing"). Every repository's lint gate runs actionlint.
  [rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711) and pull
  request 732 are open, but its last release is 2026-03-30 and its last commit
  2026-04-19 (checked 2026-11-10), so a fix may not come. jactionlint accepts it but is not taken for
  now (item 7). Not evaluated: the fork `kjanat/actionlint`, which says it is a
  drop-in CLI with `$/` and `ubuntu-26.04`, and a `paths` ignore in
  `.github/actionlint.yaml` for the two `$/` messages, as #711 suggests.
- **How, once actionlint accepts it:** rewrite the shared workflows and each
  target's own, extend `lint_workflows.sh` rule 7 to `$/` (it checks the
  sparse-checkout list for `./` refs only), re-enable the rule, and update
  each target's disabled-rules note.

### 5. Drop the `re2js` override (S)

- **What:** markdownlint 0.42.0, which markdownlint-cli2 0.24.0 pulls in, pins
  `re2js` 2.8.6 under GHSA-gg6h-894w-4m9c, fixed in 2.8.7. `overrides` in
  `files/.github/package.json` holds `re2js` at 2.9.1, the newest past the cooldown.
  markdownlint 0.42.1 (2026-11-07) pins 2.9.1 itself, but markdownlint-cli2
  0.24.0, still the newest, pins markdownlint 0.42.0. Checked 2026-11-10.
- **How:** drop the override once a markdownlint-cli2 release takes markdownlint
  0.42.1 or later and clears the cooldown.

## Platform changes with a date

### 6. `ubuntu-latest` becomes Ubuntu 26.04 between 2026-10-19 and 2026-11-19

Every shared workflow job, and this repository's own, now names
`ubuntu-26.04` rather than `ubuntu-latest`, so the next image change is a
commit and not the label moving under a run. `.github/actionlint.yaml`, shared
with every target, tells actionlint 1.7.12 the label. What changed under them,
from GitHub's image comparison (`actions/runner-images#14226`):

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

## Integrations and replacements

### 7. jactionlint in place of actionlint (_batch_, decided against for now)

- **What:** [jdx/jactionlint](https://github.com/jdx/jactionlint), an
  MIT-licensed fork of actionlint that accepts `uses: $/...`, which would
  unblock item 4. Not taken: the first release was 2026-10-05, it reached v2.3.0
  within three weeks with a major bump four days in, has shipped a minor a week
  since (v2.5.0 on 2026-11-05), and has one maintainer. Revisit once it has a settled release history, or drop
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

### 8. A shared push ruleset

Rulesets of type `push` apply to every branch and can refuse paths
(`*.key`, `*.pem`, `.env`, `secrets/`) and files over a size. One
`rulesets/push.json` rendered and diffed like the other three would make the
`.gitignore` secret patterns a server-side rule. Low value for one
maintainer whose `gitleaks` check runs on every push; worth it only if a
target gains contributors.

## More files into `files/`

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

## Known issues

### 9. Jobs that time out without doing the work

- **What:** `scripts/retried_timeouts.py` found 105 jobs since 2026-08-01 that
  hit a time limit and passed within two retries, nearly all from 2026-10-21 on
  `ubuntu-26.04`. Its outcome column shows most never ran to their limit: 58
  ended their `Complete job` step yet stayed open, 40 recorded no finished step.
  A larger limit does not help them, nor a smaller one: `rerun-timeouts.yml`'s
  5-minute job stayed open 10. Item 10 is the cause wherever a log remains, by its
  measurement below.
- **Done:** `rerun-timeouts.yml` reruns a run's failed jobs when one hit a time
  limit, at most twice, under `block` since it holds a write token; item 10 can
  fail it, which leaves that run for a rerun by hand. Limits were lowered from
  `scripts/job_durations.py`'s 20 newest passing runs: 5 minutes under a 1-minute
  longest run, else 1.5 times the longest rounded up to 5 with a floor of 10, and
  15 to 20 for jobs that compile or build an image, whose cold runs the sample may
  miss. Release and publish jobs and jobs seen under 5 times keep theirs.
- **Not done:** reporting the jobs that finished yet stayed open to GitHub. A move
  back to `ubuntu-24.04` no longer tests anything: item 10's measurement separates
  `block` from `audit` on the one image.
- **9a, rescan (done 2026-11-09):** `scripts/retried_timeouts.py` with
  `--since 2026-11-01` added 34 rows (139 in the log). 33 are item 10's kind: no
  step finished, or every step finished within a minute and the job stayed open
  to its limit; the 7 since 2026-11-03 are all of that kind, on `ubuntu-26.04`.
  The one job the limit itself killed is say-hi's
  `pinned images (trivy, advisory)` of 2026-11-02 (run 41542551840, job
  125610073245, `us-east-1`, `block`, nothing dropped): trivy downloaded its database in 4 seconds, then
  called `index.docker.io` until 23:12 with no output, and the 10-minute limit
  cancelled it; its usual run is under a minute, and attempt 2 passed. A hung
  pull, not a slow job, so the limits stand. If it recurs, `scan_pinned_images.sh`
  could pass trivy a `--timeout` under the job's limit so the report names the
  image.
- **9b, verify the rerun:** after the first automatic rerun of a `CI` run on
  `main`, that the workflows chained off `CI` fired from attempt 2, since a rerun
  started by `GITHUB_TOKEN` may not emit `workflow_run`. It lapses if item 3
  removes `rerun-timeouts.yml` first.

### 10. harden-runner `block` drops allowlisted hosts on some westus2 runners

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
  the 10 jobs that hit a limit, the 9 whose logs remain all ran `block` on
  westus2; a sample of 400 passing jobs held no `block` job on westus2, 20
  `audit` jobs on westus2, and 77 `block` jobs elsewhere. In one stuck job's post step, the runner's own
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
  covers the earlier port conflict on `127.0.0.1:53`, fixed. Checked 2026-11-07;
  v2.22.4 was still the newest release on 2026-11-10.
- **Until then:** jobs with no write token run `audit` (`release-note.yml`,
  `pages.yml`'s build, and here `checks.yml`'s two jobs and `bump-tools.yml`'s
  read-only one). Jobs that keep `block` start with a `dns-experiment` step
  that refuses the runner when `egress-dns-resolver.service` is active, before the
  agent engages, so they fail in seconds; `rerun-timeouts.yml` reruns that failure.
  `sync.yml`'s `sync` is the exception (10a).
  `scorecard.yml` has no such step, since its publish check restricts the job's
  steps, so it can still stick. Neither has been seen on a runner in the experiment:
  the first refusal, or a stuck `block` job with the step, is the check. A stopgap
  not taken: retry zizmor with `--offline` when its online audit cannot reach
  GitHub (skips `known-vulnerable-actions` on that run).
- **Recognize it:** `Region: westus2` in the job's set-up log, and in
  harden-runner's post step every `endpoint called` line has an empty
  `domain:`, with `ip address dropped` for an allowlisted host's IP.
- **10a, prove the fix:** the `dns-experiment` step refuses an experiment runner
  before harden-runner engages, so no run can show v2.22.3's fix while it is
  there. `sync.yml`'s `sync` job, this repository's alone, now reports such a
  runner with a `dns experiment` notice instead of refusing it, and keeps
  `block`. A `Sync` run that carries the notice and passes is the proof; one
  that carries it and stays open to its 10-minute limit says the fix is not on,
  and takes a rerun by hand, since `rerun-timeouts.yml` does not watch `Sync`.
  The job runs on a push to `main` that changes `files/`, `repos/` or
  `rulesets/`, weekly and on dispatch, so the first such runner may be weeks
  away; the same step in the shared `codeql.yml` would put the question to
  every target's runs. Take v2.22.4 from 2026-11-13 either way.
- **10b, remove the workaround:** once one passes, drop the step everywhere,
  with its exemption in `lint_workflows.sh` rule 6, and move the `audit` jobs
  named above back to `block`.

### 11. Sync pull requests still run sharerr-rs's `CodeQL (rust)` (S)

- **What:** 135 of its 682 runner minutes in the week measured, and 34% of its
  minutes were `ci-sync`'s. Its other Rust jobs and both Docker builds now skip
  a pull request that touches only shared CI files. This one is the shared
  `codeql.yml`, whose header says a skipped category leaves code scanning
  waiting on a result, and code scanning is in that repository's ruleset.
- **Still runs:** 7m40s on sync pull request 153 (2026-11-02), where every other
  Rust and Docker job skipped.
- **Verify first:** whether a skipped `CodeQL (rust)` holds a sync pull request's
  merge. Needs a real pull request; nothing local shows it.

### 12. shfmt and `brew style` disagree on homebrew-tap's shell layout

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

## To consider

Evaluated, not decided: nothing here is on the order of work until it is taken up.

### 13. `mise.toml` in place of `tools.txt` (_batch_, L)

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
- **How, if taken up:** try say-hi's `quick lint` job first, the cheapest way to
  measure what mise adds to a job's time and find the hosts it needs, then move
  every target as one batch.
