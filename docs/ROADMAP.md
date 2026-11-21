# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone. A
finished item moves to [CHANGELOG.md](CHANGELOG.md).

## Where it stands

As of 2026-11-20, branch `dev`, level with `main`.

- Items 17 to 21 are on `main` (pull request 44) and reached the targets
  through the sync; sharerr-rs merged its sync pull request 173 on 2026-11-18.
  Importing items 19 and 20's rulesets into each target is left for the owner.
- harden-runner v2.22.4 is on `main` here and in all five targets. None of the
  five `Sync` runs from 2026-11-16 to 11-18 carried the `dns experiment`
  notice, so 10a still waits on one that does. The targets' `CodeQL (actions)`
  runs were not read.
- Items 5 and 16, and item 14's scanner, are done in the working tree
  ([CHANGELOG](CHANGELOG.md), 2026-11-20): `tests/run.sh` passes all 20
  suites, and `scripts/check.sh` passes but for the pins, constricter, reuse
  and audit rows, which need the pinned tools and the virtual environment this
  machine lacks. `files/.claude/plan-scan` is now the scan's one source, with
  its suite in `tests/plan_scan_test.sh`; the bash 3.2 check there was skipped
  (no container engine in this session). Item 14's lint step in each target is
  left.
- Item 11 is still unanswered: sync pull request 173 ran every Rust job, so
  nothing was skipped.
- Open question: items 15 and 22 bind outside contributors' agents, which is
  the owner's call.

## Order of work

Ranked by value for size. Items are numbered through the file; a letter marks
one step of an item. S, M and L are sizes.

- Item 14, the `plan-scan` step in each target's lint job (S), in a session
  that works in the targets.
- 10a, a passing `Sync` or `CodeQL (actions)` run that carries the
  `dns experiment` notice; then 10b, the `dns-experiment` step's removal and
  its five `audit` jobs back to `block` (M).
- Item 11's check, which needs a real sync pull request (S).
- Item 3, `rerun-timeouts.yml`, after 10b (S); 3a lapses with it.
- Item 2, `block` for the remaining Linux `audit` jobs, after 10b (M).

On hold: items 4 and 6 (an actionlint release), 7 (jactionlint's release
history), 12 (shfmt's `ignore` on a single file), and 15 and 22 (the owner's
decision). Later: items 8 and 13.

## Now

### Fixes in this repository

#### 2. `block` for the remaining Linux `audit` jobs (_batch_, M)

- **What:** the macOS and Windows jobs moved to `block` on 2026-11-16
  ([CHANGELOG](CHANGELOG.md)). Most `audit` jobs left are Linux jobs that
  never had an allow list: in the targets' own workflows, sharerr-rs 16
  (`ci.yml` 9, `integration.yml` 3, `docker.yml` 2, `prepare.yml`,
  `coverage.yml`), instadroid 13 (`ci.yml` 7, `publish.yml` 3, `coverage.yml`
  2, `new-builds.yml`), homebrew-tap 3 (`ci.yml` 2, `drift.yml`) and say-hi's
  `ci.yml` 1; in `files/`, `advisories.yml` and `image-scan.yml`'s published-image
  job. Counted 2026-11-16.
- **Blocked by item 10:** a Linux job on `block` is exposed to the DNS
  experiment until 10a's proof; the macOS and Windows agents were not.
- **How:** `scripts/egress_baseline.sh <owner/repo> <workflow> 10 ubuntu` per
  workflow, as for the macOS and Windows round, one session per repository,
  say-hi first. It reads StepSecurity's public run API, so it answers for
  public repositories only.
- **Stay `audit` by decision:** `link-check.yml` (any host a doc links), the
  shared `codeql.yml`'s language jobs (extraction may resolve dependencies from
  the package index), instadroid's `cflite.yml` (OSS-Fuzz's images), sharerr-rs's
  `docker-image.yml` (a self-hosted runner label has no agent), say-hi's WSL job
  (hangs under `block`) and `release.yml`'s `brew` (runs only on a tag).

#### 3. Drop `rerun-timeouts.yml` (_batch_, S)

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
- **Verified:** the 2026-11-09 rescan found no job the lowered limits killed
  while doing its work; every retried job but one was item 10's stuck kind, and
  that one was a hung Docker Hub pull ([CHANGELOG](CHANGELOG.md), 2026-10-30).
- **3a, verify the rerun while it stays:** after the first automatic rerun of a
  `CI` run on `main`, that the workflows chained off `CI` fired from attempt 2,
  since a rerun started by `GITHUB_TOKEN` may not emit `workflow_run`. It
  lapses if this item lands first.

### Known issues

#### 10. harden-runner `block` drops allowed hosts on some westus2 runners (M)

- **What:** GitHub runs an experiment on some westus2 hosted runners that adds
  its own DNS resolver (`egress-dns-resolver.service`, on `127.0.0.100:53`).
  On those runners harden-runner's Community-tier agent sees the DNS queries
  but not the answers, so it never maps an allowed host to its IP and
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
- **Jobs that time out without doing the work:** `scripts/retried_timeouts.py`
  found 139 jobs from 2026-08-01 to 2026-11-09 that hit a time limit and passed
  within two retries, nearly all from 2026-10-21 on `ubuntu-26.04`. Most never
  ran to their limit: they ended their `Complete job` step yet stayed open, or
  recorded no finished step. A larger limit does not help them, nor a smaller
  one: `rerun-timeouts.yml`'s 5-minute job stayed open 10. This issue is the
  cause wherever a log remains. Not done: reporting the jobs that finished yet
  stayed open to GitHub. A move back to `ubuntu-24.04` no longer tests
  anything: the measurement below separates `block` from `audit` on the one
  image.
- **Measured, 2026-10-24 to 10-31,** with a one-off script over the runner region
  in each job's log, across sharerr-rs, instadroid, homebrew-tap and saffron. Of
  the 10 jobs that hit a limit, the 9 whose logs remain all ran `block` on
  westus2; a sample of 400 passing jobs held no `block` job on westus2, 20
  `audit` jobs on westus2, and 77 `block` jobs elsewhere. In one stuck job's post step, the runner's own
  connection (`Runner.Worker`) is dropped too, which is why a job stays open after
  its last step.
- **Upstream:** harden-runner v2.22.3 (2026-10-27) fixes "unexpected blocking
  of allowed connections caused by GitHub's DNS resolver and outbound proxy
  experiment on GitHub-hosted Linux runners". v2.22.4 (2026-11-06) enables that
  workaround by default when its feature flags cannot be fetched, which
  suggests v2.22.3 gates it on a flag fetched at start; it cleared the cooldown
  on 2026-11-13 and was still the newest release on 2026-11-16, when it went
  into `files/`, this repository's own workflows and every target's own
  (`scripts/bump_pins.sh`). It is on `main` here and in all five targets.
  [actions/runner-images#14925](https://github.com/actions/runner-images/issues/14925)
  was closed as completed on 2026-11-06, with no comment from GitHub on the
  DNS-observation part.
  [step-security/harden-runner#705](https://github.com/step-security/harden-runner/issues/705)
  covers the earlier port conflict on `127.0.0.1:53`, fixed.
- **Until then:** jobs with no write token run `audit` (`release-note.yml`,
  `pages.yml`'s build, and here `checks.yml`'s two jobs and `bump-tools.yml`'s
  read-only one). Jobs that keep `block` start with a `dns-experiment` step
  that refuses the runner when `egress-dns-resolver.service` is active, before the
  agent engages, so they fail in seconds; `rerun-timeouts.yml` reruns that failure.
  `sync.yml`'s `sync` and the shared `codeql.yml`'s `CodeQL (actions)` are the
  exceptions (10a).
  `scorecard.yml` has no such step, since its publish check restricts the job's
  steps, so it can still stick. No refusal, notice or stuck `block` job has been
  seen since the step went in. A stopgap
  not taken: retry zizmor with `--offline` when its online audit cannot reach
  GitHub (skips `known-vulnerable-actions` on that run).
- **Recognize it:** `Region: westus2` in the job's set-up log, and in
  harden-runner's post step every `endpoint called` line has an empty
  `domain:`, with `ip address dropped` for an allowed host's IP.
- **10a, prove the fix:** the `dns-experiment` step refuses an experiment runner
  before harden-runner engages, so no run can show harden-runner's fix while it
  is there. Two jobs report such a runner with a `dns experiment` notice instead
  of refusing it, and keep `block`: `sync.yml`'s `sync`, this repository's
  alone, and the shared `codeql.yml`'s `CodeQL (actions)`, on `main` here and in
  every target, which puts the question to every target's runs. A run of
  either that carries the notice and passes under v2.22.4 is the proof. One
  that carries it and stays open to its limit says the fix is not on; a
  `CodeQL` run is then retried by `rerun-timeouts.yml`, a `Sync` run takes a
  rerun by hand. None of the six `Sync` runs since its notice landed
  (43281842399 on 2026-11-12, five from 2026-11-16 to 11-18) carried it.
- **10b, remove the workaround:** once one passes, drop the step everywhere,
  with its exemption in `lint_workflows.sh` rule 6, and move the five `audit`
  jobs named above back to `block`. Item 2 follows.

#### 11. Sync pull requests still run sharerr-rs's `CodeQL (rust)` (S)

- **What:** 135 of its 682 runner minutes in the week measured, and 34% of its
  minutes were `ci-sync`'s. Its other Rust jobs and both Docker builds now skip
  a pull request that touches only shared CI files. This one is the shared
  `codeql.yml`, whose header says a skipped category leaves code scanning
  waiting on a result, and code scanning is in that repository's ruleset.
- **Still runs:** 7m40s on sync pull request 153 (2026-11-02), where every other
  Rust and Docker job skipped.
- **Verify first:** whether a skipped `CodeQL (rust)` holds a sync pull request's
  merge. Needs a real sync pull request that touches only shared CI files;
  nothing local shows it. Pull requests 168, 169 and 173 (2026-11-16 to 11-18)
  came since; 173 (`.gitignore`, `.gitattributes`, `.claude/rules/` and three
  more) ran every Rust job, `CodeQL (rust)` 7m51s, so it does not answer. 168
  and 169 not read.

### Safeguards to share

Files and ruleset changes that keep an agent's or a contributor's work safe,
written for these repositories rather than found by the census. Each is a kind
of file any repository may carry, so it may start with a single target
([README](../README.md), "Layout"). Every target is public, so none of these
files names a person, a machine, a path outside the repository or another
repository. Items 15 and 22 are on hold below; 16 to 21 and item 14's scanner
are in the [CHANGELOG](CHANGELOG.md).

#### 14. `plan-scan` in each target's lint job (_batch_, S)

- **What:** `files/.claude/plan-scan` and an `rg` row in `tools.txt` reach every
  target with the next sync ([CHANGELOG](CHANGELOG.md), 2026-11-20); nothing
  runs the scanner yet. say-hi commits two plans in `docs/plans/`, and every
  target receives agent rules under `.claude/rules/`, its default scope.
- **How:** in each target's own lint job, `rg` (and `gitleaks` where the target
  pins it) through `setup-tools`, then `.claude/plan-scan` with no arguments.
  Set `PLAN_SCAN_DIR` to a directory whose `allow` file holds `runner`: on a
  hosted runner the identity check reads the login `runner`, and a plan about
  CI says the word.
- **Not taken:** a default `plan-scan.paths` over `CLAUDE.md`, `README.md` and
  `docs/*.md`, which fails every target on deliberate content (the CHANGELOG
  has the counts). A target may list its own globs once those are clean.

## On hold

### Fixes in this repository, on hold

#### 4. The `$/` rewrite and zizmor `self-repository` (_batch_, M)

- **What:** Scorecard v5.6.0, which `ossf/scorecard-action` v2.5.0 ships,
  reads `uses: $/...` as a local action, so the rewrite of every
  `uses: ./.github/...` to `$/.github/...` and `self-repository` back on in
  `.github/zizmor.yml` could follow. Blocked: actionlint 1.7.12, the newest,
  rejects `$/` ("ref is missing"). Every repository's lint gate runs actionlint.
  [rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711) and pull
  request 732 are open, but its last release is 2026-03-30 and its last commit
  2026-04-19, so a fix may not come; 1.7.12 was still the newest and #711 open
  on 2026-11-16. jactionlint accepts it but is not taken for now (item 7). Not
  evaluated: the fork `kjanat/actionlint`, which says it is a drop-in CLI with
  `$/` and `ubuntu-26.04`, and a `paths` ignore in `.github/actionlint.yaml`
  for the two `$/` messages, as #711 suggests.
- **How, once actionlint accepts it:** rewrite the shared workflows and each
  target's own, extend `lint_workflows.sh` rule 7 to `$/` (it checks the
  sparse-checkout list for `./` refs only), re-enable the rule, and update
  each target's disabled-rules note.

#### 6. Drop the `ubuntu-26.04` label from `.github/actionlint.yaml` (S)

- **What:** every workflow names `ubuntu-26.04` ([CHANGELOG](CHANGELOG.md),
  2026-10-21), and `.github/actionlint.yaml`, shared with every target, tells
  actionlint 1.7.12 the label. It goes once an actionlint release knows 26.04.

### Integrations and replacements

#### 7. jactionlint in place of actionlint (_batch_, decided against for now)

- **What:** [jdx/jactionlint](https://github.com/jdx/jactionlint), an
  MIT-licensed fork of actionlint that accepts `uses: $/...`, which would
  unblock item 4. Not taken: the first release was 2026-10-05, it reached v2.3.0
  within three weeks with a major bump four days in, has shipped a minor a week
  since (v2.6.0 on 2026-11-12), and has one maintainer. Revisit once it has a
  settled release history, or drop it if actionlint accepts `$/` first.
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

### Known issues, on hold

#### 12. shfmt and `brew style` disagree on homebrew-tap's shell layout (S)

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
- **Left:** shfmt 3.14.1, still the newest on 2026-11-16, honors `ignore` only
  when it walks a directory (`shfmt -d <file>` still reformats it), so whatever
  formats one file on save must also skip a file `shfmt -f <dir>` leaves out.
  Until it does, apply `brew style --fix`'s diff by hand and do not reformat
  afterwards.

### Safeguards to share, on hold

Both wait on the owner's decision: committed agent settings and conduct bind
every contributor's agent, not only the owner's.

#### 15. A shared `.claude/settings.json` (_batch_, M)

- **What:** say-hi, sharerr-rs, instadroid and python-constricter track one,
  with no `attribution`, `plansDirectory`, deny list or hooks; homebrew-tap has
  none. A shared baseline would set `plansDirectory` to `docs/plans`, turn
  `attribution` off (no co-author trailer or session link in commits and pull
  requests), add item 14's hook, and deny the publishing commands: `git push`,
  `git commit`, `gh pr`, `gh issue` and `gh release` writes, `gh secret`,
  `gh variable` and `gh workflow run`.
- **Decide first:** committed settings bind every contributor's agent, not
  only the owner's. Attribution off and the publishing denies would apply to
  an outside contributor's Claude Code session in these repositories.
- **How:** a template, with each target's own allows in its
  `shared:if repo=<name>` block. The "leave: project settings" row in the
  table under Later changes with it.

#### 22. `AGENTS.md`, a conduct file for coding agents (_batch_, M)

- **What:** Codex, Copilot and Cursor read a root `AGENTS.md` natively, and
  Claude Code reads it through `@AGENTS.md` as the first line of `CLAUDE.md`. A
  short shared one would hold the conduct every target shares: no AI
  attribution; no secret, identifier or personal data in a file or reply; a
  step not run is reported as not run; push, tag, release or comment only on
  the developer's word; stop the services a step started. Each target's
  `CLAUDE.md` then drops what the file repeats.
- **Decide first:** this is the most visible file here. It states the owner's
  agent policy to every visitor and binds outside contributors' agents, as
  item 15 does.

## Later

### Integrations and replacements, later

#### 8. A shared push ruleset

Rulesets of type `push` apply to every branch and can refuse paths
(`*.key`, `*.pem`, `.env`, `secrets/`) and files over a size. One
`rulesets/push.json` rendered and diffed like the other three would make the
`.gitignore` secret patterns a server-side rule. Low value for one
maintainer whose `gitleaks` check runs on every push; worth it only if a
target gains contributors.

### More files into `files/`

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

### To consider

Evaluated, not decided: nothing here is on the order of work until it is taken up.

#### 13. `mise.toml` in place of `tools.txt` (_batch_, L)

- **What:** make `mise.toml` and `mise.lock` the one list of pinned CI tools, in
  place of `.github/actions/setup-tool/tools.txt`, its installer, and the
  `setup-tools` action. say-hi's mise pins are a second copy of `tools.txt`
  today, the shared `.config/mise/conf.d/ci-tools.toml`, held to it by
  `scripts/mise_pins.sh`; a single list removes the copy.
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

## Decisions

- 2026-11-17: a file joins `files/` with a single target when it is a kind of
  file any repository may carry, such as a common config or an agent rule, and
  holds nothing that could only ever apply to one repository.
- Item 2: the jobs listed under its "Stay `audit` by decision" stay `audit`.
- Item 7: jactionlint is not taken for now; revisit once it has a settled
  release history.
- Item 8: a shared push ruleset is not worth it while one maintainer works the
  targets and `gitleaks` runs on every push.
- `bug_report.yml` and `feature_request.yml` stay per-repository, and so do
  `.prettierignore`, `.typos.toml` and `.hadolint.yaml`: they share a line or
  two, and a template would be mostly per-repository blocks.
- The shared rulesets require no approving review, so the owner merges their
  own pull requests; Scorecard's Branch-Protection scores that 3/10
  ([README](../README.md), "The rulesets").

## Done

Finished items, newest first, are in [CHANGELOG.md](CHANGELOG.md).
