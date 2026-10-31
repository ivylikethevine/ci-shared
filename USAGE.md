# Usage

Which repositories receive each shared file, written by
`scripts/usage.sh` from `repos/`; run it after changing a file list there.

| File                                               | homebrew-tap | instadroid | python-constricter | say-hi | sharerr-rs | Repos |
| -------------------------------------------------- | ------------ | ---------- | ------------------ | ------ | ---------- | ----- |
| `.editorconfig`                                    | x            | x          | x                  | x      | x          | 5     |
| `.gitattributes`                                   |              | x          | x                  | x      | x          | 4     |
| `.github/CODEOWNERS`                               | x            | x          | x                  | x      | x          | 5     |
| `.github/ISSUE_TEMPLATE/config.yml`                |              | x          | x                  | x      | x          | 4     |
| `.github/actionlint.yaml`                          | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/advisory-note/action.yml`         |              | x          |                    | x      | x          | 3     |
| `.github/actions/apt/lib.sh`                       | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/fetch-latest-artifact/action.yml` |              | x          |                    | x      | x          | 3     |
| `.github/actions/mark-tree/action.yml`             |              |            |                    | x      | x          | 2     |
| `.github/actions/setup-tool/action.yml`            | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tool/install.sh`            | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tool/lib.sh`                | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tool/tools.txt`             | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tools/action.yml`           | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tools/install-missing.sh`   | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/setup-tools/resolve.sh`           | x            | x          | x                  | x      | x          | 5     |
| `.github/actions/upsert-tracking-issue/action.yml` | x            | x          | x                  | x      | x          | 5     |
| `.github/allowed_signers`                          |              | x          |                    | x      | x          | 3     |
| `.github/dependabot.yml`                           | x            | x          | x                  | x      | x          | 5     |
| `.github/osv-scanner.toml`                         |              | x          | x                  | x      | x          | 4     |
| `.github/package-lock.json`                        |              | x          | x                  | x      | x          | 4     |
| `.github/package.json`                             |              | x          | x                  | x      | x          | 4     |
| `.github/pull_request_template.md`                 |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/check_tool_versions.sh`           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/find_tree_run.sh`                 |              |            |                    | x      | x          | 2     |
| `.github/scripts/lib.sh`                           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/lint_workflows.sh`                | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/release_notes.sh`                 |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/scan_pinned_images.sh`            |              | x          |                    | x      | x          | 3     |
| `.github/scripts/trivy_scan.sh`                    |              | x          |                    |        | x          | 2     |
| `.github/workflows/advisories.yml`                 |              | x          |                    |        | x          | 2     |
| `.github/workflows/cancel-closed-pr.yml`           |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/codeql.yml`                     |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/image-scan.yml`                 |              | x          |                    | x      | x          | 3     |
| `.github/workflows/link-check.yml`                 |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/pages.yml`                      |              | x          |                    |        | x          | 2     |
| `.github/workflows/release-note.yml`               |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/rerun-timeouts.yml`             |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/scorecard.yml`                  |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/tool-versions.yml`              | x            | x          | x                  | x      | x          | 5     |
| `.github/zizmor.yml`                               | x            | x          | x                  | x      | x          | 5     |
| `.gitignore`                                       | x            | x          | x                  | x      | x          | 5     |
| `.markdownlint.yaml`                               |              | x          | x                  | x      | x          | 4     |
| `.moxide.toml`                                     |              | x          | x                  | x      | x          | 4     |
| `.prettierrc.yaml`                                 |              | x          | x                  | x      | x          | 4     |
| `.scorecard.yml`                                   |              | x          | x                  | x      | x          | 4     |
| `.shellcheckrc`                                    | x            | x          | x                  | x      | x          | 5     |
| `.vscode/settings.json`                            | x            | x          | x                  | x      | x          | 5     |
| `.zed/settings.json`                               |              | x          | x                  | x      | x          | 4     |
| `LICENSE.md`                                       | x            | x          | x                  | x      | x          | 5     |
| `LICENSES/CC-BY-4.0.txt`                           | x            | x          | x                  | x      | x          | 5     |
| `LICENSES/MIT.txt`                                 | x            | x          | x                  | x      | x          | 5     |
| `REUSE.toml`                                       | x            | x          | x                  | x      | x          | 5     |
| `_config.yml`                                      |              | x          |                    | x      | x          | 3     |
| `docs/CODE_OF_CONDUCT.md`                          | x            | x          | x                  | x      | x          | 5     |
| `lychee.toml`                                      |              | x          | x                  | x      | x          | 4     |
| **Files per repository**                           | 26           | 54         | 45                 | 53     | 56         | 56    |

## Template values

- `.gitignore` in homebrew-tap: `stray_files=true`
- every template in instadroid: `language=python`
- `.github/workflows/advisories.yml` in instadroid: `tool=pip-audit`
- `.github/workflows/image-scan.yml` in instadroid: `pins_egress=audit image_name=instadroid trivyignore=.trivyignore`
- `.github/workflows/rerun-timeouts.yml` in instadroid: `workflows=CI, Coverage, CodeQL, Scorecard, Image scan, Release note, Link check, Tool versions, Advisories`
- `.gitignore` in instadroid: `images=true stray_files=true`
- `_config.yml` in instadroid: `title=instadroid description=A real, logged-in Instagram Android app running in redroid, publishing the chronological Following feed as Atom for FreshRSS.`
- every template in python-constricter: `language=python`
- `.github/workflows/rerun-timeouts.yml` in python-constricter: `workflows=CI, Security, CodeQL, Scorecard, Release note, Link check, Tool versions`
- `.gitignore` in python-constricter: `stray_files=true`
- `.github/workflows/image-scan.yml` in say-hi: `pins_egress=block`
- `.github/workflows/rerun-timeouts.yml` in say-hi: `workflows=CI, Coverage, CodeQL, Scorecard, Image scan, Release note, Link check, Tool versions, Dependency review`
- `.gitignore` in say-hi: `images=true stray_files=true`
- `_config.yml` in say-hi: `title=say-hi description=A greeting, a prompt, and your aliases on every machine you ssh, docker, podman, nomad, or kubectl into - without installing anything there.`
- every template in sharerr-rs: `language=rust`
- `.github/workflows/advisories.yml` in sharerr-rs: `tool=cargo-deny`
- `.github/workflows/image-scan.yml` in sharerr-rs: `pins_egress=audit image_name=sharerr trivyignore=docker/.trivyignore`
- `.github/workflows/rerun-timeouts.yml` in sharerr-rs: `workflows=CI, Coverage, CodeQL, Scorecard, Image scan, Release note, Link check, Tool versions, Advisories`
- `_config.yml` in sharerr-rs: `title=sharerr description=Share your media library with friends, over the tools you already run.`
