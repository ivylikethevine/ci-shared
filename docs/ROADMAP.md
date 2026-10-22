<!-- SPDX-License-Identifier: MIT -->

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

### 1.2 Pins behind upstream (_batch_)

From `.github/scripts/check_tool_versions.sh` on 2026-10-18, each still
inside the 7-day cooldown:

| Pin                    | Pinned | Latest | Note                                          |
| ---------------------- | ------ | ------ | --------------------------------------------- |
| zizmor                 | 1.30.1 | 1.31.1 | cooling; new `cache-poisoning` cases, see 2.4 |
| trivy                  | 0.75.0 | 0.76.0 | cooling                                       |
| github/codeql-action   | 4.38.3 | 4.39.0 | cooling; needs CodeQL bundle 2.20.7 or later  |
| nfpm (say-hi)          | 2.47.0 | 2.48.0 | cooling                                       |
| terraform (sharerr-rs) | 1.16.5 | 1.16.6 | cooling                                       |
| python-constricter     | 0.3.5  | 0.3.6  | cooling                                       |

### 1.3 This repository's own policy files

- **What:** ci-shared ships `dependabot.yml`, an issue-template `config.yml`
  linking `docs/SECURITY.md` and `docs/SUPPORT.md`, and `CODEOWNERS` to every
  target, and has none of them itself: no Dependabot (Scorecard's
  Dependency-Update-Tool scores 0 and its security updates for the npm lock
  and `requirements-dev.txt` are off), no security policy, no `docs/`.
- **How:** `scripts/own_workflows.sh` grows into `own_files.sh` and renders
  `dependabot.yml` for a target named `ci-shared` (its block: github-actions
  over `/` and `/.github/actions/*`, npm under `/.github`, pip at `/`), and
  `check.sh --check`s it like the workflows. `docs/SECURITY.md` is a short
  file of this repository's own: a compromised shared file reaches five
  repositories, which is worth a private-report channel.

### 1.4 README step 3 still copies into the checkouts

- **What:** "Changing a shared file" step 3 describes `scripts/sync_local.sh`
  writing into the sibling checkouts; the working rule is that the push to
  `main` opens the sync pull requests and local checkouts are left alone,
  with `--check` for a look.
- **How:** reword step 3 to the `--check` form and move the writing form to
  the script's own header, where a first setup of a new machine still needs
  it.

### 1.5 The per-file SPDX headers come out (_batch_)

- **What:** `scripts/spdx.sh` puts an `SPDX-License-Identifier` comment at
  the top of every tracked file here and under `files/`, and `check.sh` fails
  without it. Neither reader needs it: Scorecard's License check asks the
  GitHub License API, else looks for `LICENSE.md`, and REUSE is met by
  `REUSE.toml` (`path = "**"`) with `LICENSES/MIT.txt`, which `files/` now
  carries to every target. A regenerated file (`requirements-dev.txt`) loses
  the line on every compile and fails the check until it is put back.
- **How:** delete `scripts/spdx.sh`, its suite, the `spdx` check, the README
  row and the `&& scripts/spdx.sh` note in `requirements-dev.in`; strip the
  comment from every file here and under `files/`, which the sync carries to
  the targets (each target's roadmap holds the item for its own files); run
  5.2's `reuse lint` once to confirm the TOML alone passes.

### 1.6 Two triggers that never fire as described

- **`scorecard.yml`'s `branch_protection_rule`:** the event exists for classic
  branch protection only; GitHub Actions has no event for ruleset changes, and
  every target is on rulesets. Harmless (the weekly cron re-grades), but the
  header promises a re-grade "the moment a rule changes". Drop the trigger and
  the sentence, or keep it with the caveat.
- **`sync.yml` on a `rulesets/` push:** the push trigger lists `files/**` and
  `repos/**`, so a ruleset edit waits for the weekly `rulesets.sh diff`. Add
  `rulesets/**` to the paths and run the diff step on a push that touched it.

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

### 2.2 Node 24 in say-hi's lint job (_batch_)

- **What:** `checks.yml` here is on `node-version: "24"`; say-hi's `ci.yml`
  lint job still pins 22, in maintenance since October 2025 and end-of-life
  2027-04-30. Only markdownlint-cli2 and prettier run on it.
- **How:** `"24"` in say-hi's `ci.yml`, with the next batch, and the `node`
  line of `tools.txt`'s floating-tools note.

### 2.3 Dependabot's default cooldown

- **What:** since 2026-07-14 Dependabot waits three days by default; the
  shared `dependabot.yml` sets seven explicitly on every entry, which wins.
  Nothing to change; the `COOLDOWN_DAYS` comment in `check_tool_versions.sh`
  still mirrors it.

### 2.4 zizmor 1.31 and CodeQL action 4.39

- **zizmor 1.31.0:** `dangerous-triggers` now treats `issue_comment` as
  dangerous (unused here); `cache-poisoning` flags `cache-mode: write` under
  dangerous triggers and skips `cache-mode: none` (nothing sets either);
  `unpinned-images` and `self-hosted-runner` are more precise. Expect no new
  findings, but run `check.sh` with the new pin before the batch merges.
- **codeql-action 4.39.0:** minimum CodeQL bundle 2.20.7, which the hosted
  runners' bundle meets; `analyze` now warns on a wrong `checkout_path`
  (unset here).

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

### 5.2 `reuse lint`

`REUSE.toml` and `scripts/spdx.sh` exist, and nothing validates the result.
`reuse` from PyPI, pinned in `requirements-dev.in`, run as `reuse lint` in
`check.sh`, confirms every file is covered and the `LICENSES/` text matches.

### 5.3 kcov from apt once 26.04 ships 43

`tests/coverage.sh` needs kcov 43, built from source on a cache miss (a
minute of cmake and its build deps). Ubuntu 24.04 packages 42; if 26.04
packages 43 or later, `_ci_apt_install kcov` replaces the `cmake` row for
this repository, and the row stays for say-hi only if it still needs the
source build.

### 5.4 `pinact run --check`

If 3.2 adopts pinact for action SHAs, its check mode joins `check.sh` beside
`lint_workflows.sh`: it also verifies that each SHA is reachable from the
tag its comment names, which rule 5 does not.
