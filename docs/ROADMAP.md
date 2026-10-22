# Roadmap

What this repository and the files it ships could take next, from a reading of
the whole tree, a run of its own checks and drift report, a census of the
checkouts beside it, and the upstream state of each tool and GitHub feature in
play. Each item says what, why, how, and what to verify first. Items marked
_batch_ are shared CI items: they go to every repository as one hand-run batch
([README](../README.md), "Checking this repository"), never to one alone.

## 1. Fixes in this repository

### 1.1 The `$/` rewrite and zizmor `self-repository` (_batch_)

- **What:** Scorecard v5.6.0, which `ossf/scorecard-action` v2.5.0 ships,
  reads `uses: $/...` as a local action, so the rewrite of every
  `uses: ./.github/...` to `$/.github/...` and `self-repository` back on in
  `.github/zizmor.yml` could follow. Blocked: actionlint 1.7.12, the newest,
  rejects `$/` ("ref is missing"), and no actionlint issue or pull request
  tracks it. Every repository's lint gate runs actionlint.
- **How, once actionlint accepts it:** rewrite the shared workflows and each
  target's own, extend `lint_workflows.sh` rule 7 to `$/` (it checks the
  sparse-checkout list for `./` refs only), re-enable the rule, and update
  each target's disabled-rules note. The harden-runner `block` move for the
  macOS and Windows jobs is the other open batch item; it lives in the
  targets' own workflows, one session per repository.

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
- **Left:** the first run on the image of each other shared workflow and of
  every target's own, all now named `ubuntu-26.04` too. say-hi's two Linux
  suite jobs are renamed `fast suites (ubuntu-26.04)` and
  `lint suites (ubuntu-26.04)`, and its `[rulesets.main]` checks with them:
  re-import `scripts/rulesets.sh render say-hi main` on GitHub when the
  renamed jobs reach `main`, or pull requests wait on checks that never
  report.
- **Still exposed:** `checks.yml` and `coverage` build their venv on the
  system python3 (3.14: fine for constricter's `min-python = "3.11"` and
  coverage 7.16); `image-scan.yml` meets docker 29.

### 2.2 Dependabot's default cooldown

- **What:** since 2026-07-14 Dependabot waits three days by default; the
  shared `dependabot.yml` sets seven explicitly on every entry, which wins.
  Nothing to change; the `COOLDOWN_DAYS` comment in `check_tool_versions.sh`
  still mirrors it.

## 3. Integrations and replacements

### 3.1 One GitHub App in place of five fine-grained tokens

- **What:** each target's sync token is a fine-grained PAT with an expiry,
  renewed by hand when `scripts/check_tokens.sh` fails the weekly run. A
  GitHub App installed on the five targets (and this repository, for 3.2)
  mints a one-hour installation token per run through
  `actions/create-github-app-token`, whose `repositories` input scopes each
  token to one target, so the per-target isolation the README asks for
  stays. The secret becomes the App's private key, which does not expire.
- **Keeps:** the SSH signing key and `create_commit`'s verification (the
  signature is checked against the committer email's registered key, not the
  token), `check_protection.sh` (the App is the user whose bypass is read;
  not a bypass actor, so `never`), the `sync` environment.
- **Drops:** `check_tokens.sh` and its job output, the five
  `SYNC_TOKEN_<NAME>` secrets and the `env:` block that names them (new
  targets then need no secret), the README's expiry section.
- **Verify first:** on one target, that a Git data API commit carrying the
  SSH `signature` verifies when created with an App token, and that the
  App's bypass reads `never` on both rulesets.

### 3.2 Bumps as a pull request, not a hand edit

The weekly `tool-versions` issue already names every bump and, for action
SHAs, the commit to pin. Three ways to turn it into a pull request on this
repository, which the sync then carries everywhere:

- **In-house `--apply`** (recommended): `check_tool_versions.sh` gains a mode
  that edits what it reported: `tools.txt` rows (pin, then the sha256 by
  fetching the new asset for each platform the row names), the `-> @sha`
  lines across every `uses:`, `npm install --prefix .github <pkg>@<ver>`
  for the Markdown tools, `pip-compile --upgrade-package` for
  `requirements-dev.in`. A workflow runs it after the weekly check and opens
  one pull request. The sha256 recomputation is the one step no off-the-shelf
  tool does for this roster format.
- **pinact** (v5.0.0, 2026-09-12) for the action SHAs alone: `pinact run
--update` rewrites `uses:` pins with their version comments and `pinact run
--check` is a lint; it does not know `tools.txt` or the npm lock.
- **Renovate**, as the README described it: self-hosted through
  `renovatebot/github-action` (v46.3.8), Renovate 44.3.1 or later
  (CVE-2026-88884), regex custom managers for `tools.txt` plus
  `postUpgradeTasks` for the sha256, `ignorePaths` for the root symlinks, its
  endpoints in harden-runner. A second bot and a config dialect for a roster
  the in-house script already parses.
- **Either way** the pull request edits `.github/workflows/`, which
  `GITHUB_TOKEN` may not push: the App of 3.1 (installed on this repository
  too) is the token.

### 3.3 "Require actions to be pinned to a full-length commit SHA"

- **What:** a repository setting (Settings → Actions → General) that makes
  GitHub refuse an unpinned `uses:` at run time; reusable workflows stay
  exempt. `lint_workflows.sh` rule 5 enforces the same in-tree, but only on a
  branch that runs the lint.
- **How:** switch it on in every repository by hand (no REST field is
  documented) and record it in the README beside the rulesets; `rulesets.sh
diff` cannot see it.

### 3.4 Immutable releases on the releasing targets

- **What:** generally available since 2025-10-28: once on, every published
  release's tag and assets are locked and each release carries a Sigstore
  attestation. It complements `protect-stable` (which guards the tag refs)
  and `.github/allowed_signers` (which gates signing). All-or-nothing per
  repository, so a repository with a moving tag cannot take it.
- **How:** a target-side setting for say-hi, sharerr-rs, instadroid and
  python-constricter; `scripts/rulesets.sh diff` could report it beside the
  rulesets if the repository API exposes the flag (verify).

### 3.5 This repository's own `main` under the shared rulesets

A push to `main` here opens a pull request in every target, so `main` needs
the protection `check_protection.sh` checks there: `rulesets/main.json`
rendered for a target named `ci-shared` with required checks `Checks`,
`Coverage` and `CodeQL (actions)`, and `check_protection.sh` run on this
repository in the weekly job. The `sync` environment already limits the
secrets to `main`.

### 3.6 A shared push ruleset

Rulesets of type `push` apply to every branch and can refuse paths
(`*.key`, `*.pem`, `.env`, `secrets/`) and files over a size. One
`rulesets/push.json` rendered and diffed like the other three would make the
`.gitignore` secret patterns a server-side rule. Low value for one
maintainer whose `gitleaks` check runs on every push; worth it only if a
target gains contributors.

## 4. More files into `files/`

From `scratch/near_census.py --normalize` over the sibling checkouts. The
template engine's `shared:if repo=<name>` blocks already carry per-target
rows in `dependabot.yml` and `tools.txt`, so a file that is mostly common
with a per-repository tail is a template, not a per-repository file.

| Path                    | Held by                     | Alike                                 | Call                                                |
| ----------------------- | --------------------------- | ------------------------------------- | --------------------------------------------------- |
| `.scorecard.yml`        | say-hi, sharerr-rs          | fuzzing and contributors notes common | template; instadroid and python-constricter get one |
| `.prettierignore`       | 4 repos, 5 to 8 lines       | differ by build dirs                  | template with repo blocks                           |
| `.typos.toml`           | 4 repos, 14 to 50 lines     | a common head, per-repo words         | template with repo blocks                           |
| `.hadolint.yaml`        | say-hi, sharerr-rs (34, 29) | instadroid's is 3 lines               | template for the two                                |
| `.tool-versions`        | 3 repos, 2 to 4 lines       | different tools                       | leave                                               |
| `docs/GOVERNANCE.md`    | 3 repos, 51 to 82 lines     | ratio 0.24 to 0.27                    | leave, or template its policy sections              |
| `.claude/settings.json` | 3 repos                     | differ                                | leave: project settings                             |

`bug_report.yml` and `feature_request.yml` stay per-repository by decision.

## 5. Checks this repository could run on itself

### 5.1 Offline link check

Every target's `ci.yml` runs `lychee --offline` over its Markdown; `check.sh`
runs `lychee` not at all, while `link-check.yml` sweeps external links weekly.
Add `lychee --offline --include-fragments --config lychee.toml` over the
tracked `*.md` (the pin is in `tools.txt`), so a renamed heading in the
README fails here first.

### 5.2 kcov from apt once 26.04 ships 43

`tests/coverage.sh` needs kcov 43, built from source on a cache miss (a
minute of cmake and its build deps). Ubuntu 24.04 packages 42; if 26.04
packages 43 or later, `_ci_apt_install kcov` replaces the `cmake` row for
this repository, and the row stays for say-hi only if it still needs the
source build.

### 5.3 `pinact run --check`

If 3.2 adopts pinact for action SHAs, its check mode joins `check.sh` beside
`lint_workflows.sh`: it also verifies that each SHA is reachable from the
tag its comment names, which rule 5 does not.

## 6. Known issues

### 6.1 harden-runner `block` drops allowlisted hosts on some westus2 runners

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
