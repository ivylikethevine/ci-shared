# Changelog

What changed in this repository and the files it ships, newest first. A
[roadmap](ROADMAP.md) item moves here when it is done, with what it left in
force; nothing checks this file.

## 2026-11-16

### A target's tests run against `files/` before a sync

- **Why:** say-hi's sync pull request 285 failed its coverage sweep: its
  `drift` suite holds its `mise.toml` to the synced `tools.txt`, and the tool
  bump moved `tools.txt` alone. A target's own file cannot change in the sync
  pull request, so it took a commit by hand on `ci-sync`.
- **The pins:** `files/.config/mise/conf.d/ci-tools.toml`, which only say-hi
  receives, holds the `tools.txt` pins as mise reads them, beside say-hi's
  `mise.toml` (mise 2026.11.8 reads a checkout's `.config/mise/conf.d/`, and
  trusting the checkout covers it). `scripts/mise_pins.sh`, in `check.sh`,
  fails a pin that parts from `tools.txt`; `scripts/apply_bumps.sh` moves both.
- **The canary:** `repos/<name>.toml`'s `canary` names the target's suites that
  read shared files; `scripts/canary.sh` runs them on a clone of its sync
  branch with `files/` written in, in `checks.yml`'s canary job. say-hi's are
  `drift`, `tools` and the five `packaging` suites, 6 seconds on a dev machine. On say-hi's
  `main` before 285 merged it failed `drift` on the four pins, as the sync pull
  request had.

### harden-runner `block` on macOS and Windows jobs (_batch_)

- harden-runner v2.20.0 supports `egress-policy: block` on GitHub's macOS and
  Windows runners in the free tier. `scripts/egress_census.sh` lists the jobs
  and `scripts/egress_baseline.sh` reads each job's endpoints from its audit
  runs for `allowed-endpoints`.
- **say-hi:** `test-macos`, `windows-client.yml`'s x64 legs and
  `windows-e2e.yml`'s OpenSSH job pass under `block` (pull request run
  42959387908; the Windows jobs again on `main`, run 42961496714).
- **homebrew-tap:** the macOS leg of `ci.yml`'s `test` passes under `block` on
  `main` (run 42941662948), through a `runner.os` expression; its Linux leg
  stays `audit`.
- **python-constricter:** `ci.yml`'s `test` and `compiled` pass under `block`
  on every leg (pull request run 42942084798). `build.yml`'s `compiled` passed
  on every leg of a dispatch on `dev` (run 43964697378, 21 jobs), before any
  tag ran it. Its harden-runner logs drop only the runners' own background
  traffic: Apple's daemons and `timed`'s NTP on macOS, and six Canonical
  addresses (`185.125.190.105` to `.110`) as the agent starts on two Linux
  legs. Two of its legs ran on westus2 and passed.
- **Stay `audit`:** say-hi's `windows-e2e.yml` WSL job, whose distribution's
  connections hang under `block` even to an allowed host, so setup-wsl timed
  out (run 42940405659); say-hi's `release.yml` `brew`, which runs only on a
  tag push, so its first `block` run would be a release; the weekly external
  link check. Windows arm64 has no agent. sharerr-rs and instadroid have no
  macOS or Windows job.
- **For the next target:** the baseline held endpoint data for 3 of `ci.yml`'s
  last 10 passing runs, so a host only a cold cache fetches is in none of them;
  read the action's source for it (setup-wsl downloads its distribution from
  `releases.ubuntu.com`). The Windows agent names a WSL distribution's apt
  mirrors on 443 where apt's stock sources are http, so list both ports.
  harden-runner's README still says Windows and macOS are audit only, against
  v2.20.0's release note and the action's source, which hand `block` and the
  list to both agents.

## 2026-11-12

### The scratch README moved to `scripts/scratch/README.md`

- Every target keeps its one-off scripts under `scripts/scratch/`, not a root
  `scratch/`; say-hi skips the shared copy, since its `scripts/` ships to users
  and its one-offs live in `tests/scratch/`. The sync never deletes a file, so
  each target moved its old copy by hand.

## 2026-11-11

### `cancel-closed-pr.yml` dropped (_batch_)

- Gone from `files/`, `repos/_base.toml` and every target that held it
  (say-hi, sharerr-rs, instadroid, python-constricter); a merged or closed
  PR's in-flight runs now finish on their own. `rerun-timeouts.yml`, the
  other half of roadmap item 3, stays until item 10 closes.

## 2026-11-10

### Stale `setup-tool/action.yml` deleted in every target (_batch_)

- The sync writes files and never deletes one, so the `action.yml` that
  `setup-tools` replaced on 2026-11-08 stayed in each target until deleted by
  hand. It is gone from `main` in all five (say-hi, sharerr-rs, instadroid,
  python-constricter, homebrew-tap); `install.sh`, `lib.sh` and `tools.txt`
  stay beside it as `setup-tools`' backend.

## 2026-11-09

### `sync-health` issue closed

- The weekly run of 2026-11-09 (42721602217) passed every check, which closed
  #4, the `sync-health` issue left open when the sync App went live on
  2026-10-28. The first weekly run under the App (41540975712, 2026-11-02) had
  failed only the rulesets diff: three live `main` rulesets had dropped entries
  `repos/` still held, corrected in #33 (Trivy out of instadroid's and
  sharerr-rs's `code_scanning_tools`, say-hi's two `e2e` contexts out of its
  required checks).
- Still by hand per target: a mint step in `sync.yml`, which
  `scripts/check.sh` fails without.

## 2026-11-08

### Immutable releases on every releasing target

- Once on, a published release's tag and assets are locked and the release
  carries a Sigstore attestation, beside `protect-stable` and
  `.github/allowed_signers`. On in sharerr-rs and python-constricter since
  2026-10-31 and in say-hi and instadroid since 2026-11-08, as is the
  SHA-pinning requirement in every repository, both set by hand with the
  README's `gh api` calls; `immutable_releases = true` is in all four
  `repos/*.toml`. `scripts/rulesets.sh diff` compares them when its token has
  Administration read, which the sync App lacks (granting it also needs
  `permission-administration: read` on `sync.yml`'s mint steps), so the weekly
  run names them as hidden.
- say-hi (`7e6daa3a0f0da589e24933b78e2c4a641df9dc33`): `publish` creates a
  draft, attaches every asset and the package repository, then publishes with
  `gh release edit --draft=false`, in a step that runs whether the package
  repository attached or not. A new `demo` job renders the packages tape at the
  tag, so `demo.gif` goes on with the rest; `demos.yml`'s `attach` job is gone.
  `gh_asset.sh` reads the release id off the release list, since
  `releases/tags/<tag>` answers 404 for a draft.
- instadroid (#117): `publish.yml`'s `release` job creates a draft, uploads the
  deploy bundle, then publishes; a re-run against a published release edits
  only its notes.
- Proved: say-hi v0.8.5 (13 assets) and instadroid v0.2.0, both published
  2026-11-08, show `immutable: true` on the releases API. homebrew-tap and
  ci-shared publish no releases, so the setting has nothing to lock there.

### `setup-tool` replaced by `setup-tools` (_batch_)

- `setup-tool/action.yml` is gone from `files/` and `repos/_base.toml`;
  `install.sh`, `lib.sh` and `tools.txt` stay in `setup-tool/` as
  `setup-tools`' backend, and `install.sh` no longer writes `image=`
  (`resolve.sh` reads `$ImageOS` itself). The shared callers
  (`advisories.yml`, `image-scan.yml`, `link-check.yml`) call `setup-tools`,
  and `image-scan.yml`'s and sharerr-rs `docker.yml`'s sparse lists hold both
  directories.
- Every target's own caller moved (sharerr-rs `ci.yml`, whose terraform path
  filter gains `setup-tools/`, `docker.yml` and `coverage.yml`; instadroid
  `publish.yml`; python-constricter `ci.yml` and `security.yml`; say-hi
  `usage.yml`, whose `freeze` the release suite's row check now reads), and the
  sync PRs carrying the `files/` half merged in all five targets (say-hi 280,
  sharerr-rs 160, instadroid 123, python-constricter 82, homebrew-tap 93). No
  `uses:` names `setup-tool` in any target's `main`. Each tool downloads once
  more, since the cache key changed.

## 2026-11-06

### The targets' own action SHAs (_batch_)

- Every target's own workflows and actions, the files the sync does not
  deliver, are on `files/`' pins or the ones their `tool-versions` issues
  offered: harden-runner v2.22.3 everywhere, this repository and `files/`
  included; docker/login-action v4.7.0, codeql upload-sarif v4.39.1,
  setup-python v7.1.0, rust-cache v2.9.3, setup-uv v10.3.2, cibuildwheel v4.3.4
  and openbsd-vm v1.4.9 where used. `scripts/stale_pins.sh` lists none behind;
  `scripts/bump_pins.sh` makes the next round's edits.
- `setup-tool`'s `version` and `sha256` inputs went in the same round:
  `install.sh` reads the row's pin and sha256 alone.
- Left in the targets' issues, not action SHAs: say-hi's bashcov 4.0.1 and its
  `bash:3.2` digest.

## 2026-11-02

### Bumps as a pull request, not a hand edit

- `.github/workflows/bump-tools.yml` runs weekly after the version check.
  `check_tool_versions.sh` stays read-only and lists what is behind in
  `CI_FIX_LIST`; `scripts/apply_bumps.sh` edits it, in this repository alone
  since the sync owns the targets' copies and only this repository's manifest
  kinds are handled: `tools.txt` rows with each asset's sha256, every `uses:`,
  the inline pin, the npm manifest and lock, and the `.in` files and their
  locks. `scripts/bump_pr.sh` writes one draft pull request on `tool-bumps`, in
  a job of its own holding the App's token; a commit naming no author is signed
  by GitHub for the App, so it needs no SSH key and keeps file modes.
- The weekly run of 2026-11-02 (41491501365) found a bump and opened pull
  request 31 (python-constricter 0.4.2 to 0.4.3). Its commit `445647e` shows as
  verified, and the pull request job, under `block`, downloaded the artifact
  with `results-receiver` alone allowed.
- Not taken: pinact (v5.0.0), whose `pinact run --check` would add that each
  SHA is reachable from the tag its comment names, which rule 5 does not; and
  self-hosted Renovate (44.3.1 or later for CVE-2026-88884), a second bot and a
  config dialect for a roster the check already parses.

## 2026-10-31

### Simplifications

The review's 22 items are done. What they left in force:

- A label is created only with an issue, so a color or description changed in a
  workflow reaches GitHub only with the next new issue.
- `fetch-latest-artifact`'s `artifact-name` is a name or a `{a,b}` list, the
  forms every caller uses; a wildcard no longer matches. `find_tree_run.sh`
  keeps its run lookups for the event and conclusion, which an artifact does
  not carry.
- `link-check.yml` keeps `upsert-tracking-issue`'s `body-file`, since lychee's
  report is Markdown.
- `lint_workflows.sh` rule 7 does not judge an indented `source` in a script:
  it is conditional, and `setup-tool`'s `install.sh` reaches its apt library
  only for some kinds. A sparse checkout of an action or of `trivy_scan.sh`
  lists `lib.sh` too.
- `scratch/README.md` is shared and skipped by homebrew-tap, which has no
  `scratch/`, and by python-constricter, since the sync would overwrite its own
  README and the per-script list in it; drop that skip to replace them.

## 2026-10-30

### Lower job time limits, and a rerun for jobs that hit one

- `rerun-timeouts.yml` reruns a run's failed jobs when one hit a time limit, at
  most twice, under `block` since it holds a write token; roadmap item 10 can
  fail it, which leaves that run for a rerun by hand. It goes with roadmap
  item 3.
- Limits come from `scripts/job_durations.py`'s 20 newest passing runs: 5
  minutes under a 1-minute longest run, else 1.5 times the longest rounded up
  to 5 with a floor of 10, and 15 to 20 for jobs that compile or build an
  image, whose cold runs the sample may miss. Release and publish jobs and jobs
  seen under 5 times keep theirs.
- A rescan on 2026-11-09 (`scripts/retried_timeouts.py --since 2026-11-01`)
  added 34 rows, 139 in the log. 33 are item 10's kind: no step finished, or
  every step finished within a minute and the job stayed open to its limit.
  The one job a limit itself killed is say-hi's `pinned images (trivy,
advisory)` of 2026-11-02 (run 41542551840, job 125610073245): trivy
  downloaded its database in 4 seconds, then called `index.docker.io` with no
  output until the 10-minute limit; its usual run is under a minute, and
  attempt 2 passed. A hung pull, not a slow job, so the limits stand. If it
  recurs, `scan_pinned_images.sh` could pass trivy a `--timeout` under the
  job's limit so the report names the image.

## 2026-10-28

### One GitHub App in place of five fine-grained tokens

- `sync.yml` mints one token per target through
  `actions/create-github-app-token` v3.3.0, `repositories` scoping each to its
  target, and a `tokens` step exports them as the `SYNC_TOKEN_<NAME>` the
  scripts already read, so the scripts and their suites keep their contract.
  `check_tokens.sh` and its suite are gone; the health issue's `tokens` line
  now means the App minted no token for a target. The README's "The sync App"
  section has the permissions and credentials.
- Keeps: the SSH signing key and `create_commit`'s verification (the signature
  is checked against the committer email's registered key, not the token),
  `check_protection.sh` (the App is the actor whose bypass is read; not a
  bypass actor, so `never`), the `sync` environment.
- Live since 2026-10-28: the App is created and installed, its credentials set,
  and the change merged to `main`. Dry runs 40751549579 (homebrew-tap) and
  40751746191 (every target) minted all five tokens, and `check_protection.sh`
  passed every target's `main` and `dev` with the App's token. The five
  `SYNC_TOKEN_<NAME>` secrets are deleted and their PATs revoked. The first
  commit written with an App token, homebrew-tap's `db047dd` (pull request 82),
  shows as verified.
- The mint steps share one `with:` through a YAML anchor, reading
  `repositories` from each step's `env.TARGET`. That form minted all five
  tokens on 2026-11-02, in the push run (41534178362), which opened the sync
  pull requests, and in the weekly run, whose health issue has no `tokens`
  line.

## 2026-10-21

### Every workflow names `ubuntu-26.04`

- `ubuntu-latest` moves to Ubuntu 26.04 between 2026-10-19 and 2026-11-19.
  Every shared workflow job, and this repository's own, names `ubuntu-26.04`
  instead, so the next image change is a commit and not the label moving under
  a run. `.github/actionlint.yaml` tells actionlint 1.7.12 the label until a
  release knows it (roadmap item 6). What changed, from GitHub's image
  comparison (`actions/runner-images#14226`):

| Tool           | 24.04    | 26.04                                                           |
| -------------- | -------- | --------------------------------------------------------------- |
| system python3 | 3.12     | 3.14 (3.10, 3.11, 3.13 no longer cached)                        |
| node           | 22       | 24 (22 still cached)                                            |
| docker         | 28.0.4   | 29.4.2, compose 5.1.3                                           |
| cmake          | 3.31.6   | latest                                                          |
| gcc            | 12 to 14 | 13 to 15                                                        |
| removed        |          | miniconda, julia, mercurial, pulumi, fastlane, global npm tools |

- Proved since: instadroid's `main` CI (run 41258224153, 2026-10-31) and
  `image-scan.yml` under docker 29 in sharerr-rs (run 41302164981,
  2026-11-01). say-hi's live `main` ruleset requires its renamed suite jobs.
- Kept for it: `setup-tools`' cache key carries the image name (`ImageOS`), so
  a tool built from source on 24.04 (mandoc) is not restored on 26.04;
  `apt/lib.sh` drops vendor `*.sources` files as well as `*.list`;
  `checks.yml` takes a `runner` input on dispatch.

## 2026-10-18

### Dependabot's default cooldown

- Since 2026-07-14 Dependabot waits three days by default; the shared
  `dependabot.yml` sets seven explicitly on every entry, which wins. Nothing to
  change; `COOLDOWN_DAYS` in `check_tool_versions.sh` defaults to the same
  seven.
