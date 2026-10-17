<!-- SPDX-License-Identifier: MIT -->

# Usage

Which repositories receive each shared file, written by
`scripts/usage.sh` from `repos/`; run it after changing a file list there.

| File                                               | homebrew-tap | instadroid | python-constricter | say-hi | sharerr-rs | Repos |
| -------------------------------------------------- | ------------ | ---------- | ------------------ | ------ | ---------- | ----- |
| `.editorconfig`                                    | x            | x          | x                  | x      | x          | 5     |
| `.gitattributes`                                   |              | x          | x                  | x      | x          | 4     |
| `.github/CODEOWNERS`                               | x            | x          | x                  | x      | x          | 5     |
| `.github/ISSUE_TEMPLATE/config.yml`                |              | x          | x                  | x      | x          | 4     |
| `.github/actions/advisory-note/action.yml`         |              | x          |                    | x      | x          | 3     |
| `.github/actions/apt/lib.sh`                       | x            | x          |                    | x      | x          | 4     |
| `.github/actions/fetch-latest-artifact/action.yml` |              | x          |                    | x      | x          | 3     |
| `.github/actions/mark-tree/action.yml`             |              |            |                    | x      | x          | 2     |
| `.github/actions/setup-tool/action.yml`            | x            | x          |                    | x      | x          | 4     |
| `.github/actions/setup-tool/install.sh`            | x            | x          |                    | x      | x          | 4     |
| `.github/actions/setup-tool/lib.sh`                | x            | x          |                    | x      | x          | 4     |
| `.github/actions/setup-tools/action.yml`           | x            | x          |                    | x      | x          | 4     |
| `.github/actions/setup-tools/install-missing.sh`   | x            | x          |                    | x      | x          | 4     |
| `.github/actions/setup-tools/resolve.sh`           | x            | x          |                    | x      | x          | 4     |
| `.github/actions/upsert-tracking-issue/action.yml` | x            | x          | x                  | x      | x          | 5     |
| `.github/allowed_signers`                          |              | x          |                    | x      | x          | 3     |
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
| `.github/workflows/codeql.yml`                     |              | x          |                    | x      | x          | 3     |
| `.github/workflows/image-scan.yml`                 |              | x          |                    | x      | x          | 3     |
| `.github/workflows/link-check.yml`                 |              | x          |                    | x      | x          | 3     |
| `.github/workflows/pages.yml`                      |              | x          |                    |        | x          | 2     |
| `.github/workflows/release-note.yml`               |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/scorecard.yml`                  |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/tool-versions.yml`              | x            | x          | x                  | x      | x          | 5     |
| `.github/zizmor.yml`                               | x            | x          | x                  | x      | x          | 5     |
| `.gitignore`                                       | x            | x          | x                  | x      | x          | 5     |
| `.markdownlint.yaml`                               |              | x          | x                  | x      | x          | 4     |
| `.moxide.toml`                                     |              | x          | x                  | x      | x          | 4     |
| `.prettierrc.yaml`                                 |              | x          | x                  | x      | x          | 4     |
| `.shellcheckrc`                                    | x            | x          | x                  | x      | x          | 5     |
| `.vscode/settings.json`                            | x            | x          | x                  | x      | x          | 5     |
| `.zed/settings.json`                               |              | x          | x                  | x      | x          | 4     |
| `LICENSE.md`                                       | x            | x          | x                  | x      | x          | 5     |
| `_config.yml`                                      |              | x          |                    | x      | x          | 3     |
| `docs/CODE_OF_CONDUCT.md`                          | x            | x          | x                  | x      | x          | 5     |
| `lychee.toml`                                      |              | x          | x                  | x      | x          | 4     |
| **Files per repository**                           | 20           | 46         | 28                 | 45     | 48         | 48    |

## Template values

- `.gitignore` in homebrew-tap: `repo=homebrew-tap stray_files=true claude_settings=untracked`
- `.gitattributes` in instadroid: `repo=instadroid`
- `.github/ISSUE_TEMPLATE/config.yml` in instadroid: `repo=instadroid blank_issues=true doctor=scraper.py doctor`
- `.github/pull_request_template.md` in instadroid: `repo=instadroid`
- `.github/workflows/advisories.yml` in instadroid: `python=true tool=pip-audit`
- `.github/workflows/codeql.yml` in instadroid: `language=python Language=Python`
- `.github/workflows/image-scan.yml` in instadroid: `pins_egress=audit image_name=instadroid trivyignore=.trivyignore release_workflow=publish.yml`
- `.gitignore` in instadroid: `repo=instadroid images=true stray_files=true python=true jekyll=true`
- `.moxide.toml` in instadroid: `excluded="local", "_site"`
- `.vscode/settings.json` in instadroid: `python=true`
- `.zed/settings.json` in instadroid: `python=true`
- `_config.yml` in instadroid: `repo=instadroid title=instadroid description=A real, logged-in Instagram Android app running in redroid, publishing the chronological Following feed as Atom for FreshRSS.`
- `.github/ISSUE_TEMPLATE/config.yml` in python-constricter: `repo=python-constricter blank_issues=false discussions=true`
- `.github/pull_request_template.md` in python-constricter: `repo=python-constricter`
- `.gitignore` in python-constricter: `repo=python-constricter stray_files=true claude_settings=untracked python=true`
- `.moxide.toml` in python-constricter: `excluded="local"`
- `.vscode/settings.json` in python-constricter: `python=true`
- `.zed/settings.json` in python-constricter: `python=true`
- `.github/ISSUE_TEMPLATE/config.yml` in say-hi: `repo=say-hi blank_issues=true discussions=true doctor=hi --doctor --json`
- `.github/pull_request_template.md` in say-hi: `repo=say-hi`
- `.github/workflows/image-scan.yml` in say-hi: `pins_egress=block repo=say-hi`
- `.gitignore` in say-hi: `repo=say-hi images=true stray_files=true`
- `.moxide.toml` in say-hi: `excluded="dist"`
- `.vscode/settings.json` in say-hi: `repo=say-hi`
- `.zed/settings.json` in say-hi: `repo=say-hi`
- `_config.yml` in say-hi: `repo=say-hi title=say-hi description=A greeting, a prompt, and your aliases on every machine you ssh, docker, podman, nomad, or kubectl into - without installing anything there.`
- `.github/ISSUE_TEMPLATE/config.yml` in sharerr-rs: `repo=sharerr-rs blank_issues=true discussions=true doctor=sharerr doctor`
- `.github/pull_request_template.md` in sharerr-rs: `repo=sharerr-rs`
- `.github/workflows/advisories.yml` in sharerr-rs: `rust=true tool=cargo-deny`
- `.github/workflows/codeql.yml` in sharerr-rs: `language=rust Language=Rust`
- `.github/workflows/image-scan.yml` in sharerr-rs: `pins_egress=audit repo=sharerr-rs image_name=sharerr trivyignore=docker/.trivyignore release_workflow=docker.yml`
- `.gitignore` in sharerr-rs: `repo=sharerr-rs mcp=true rust=true jekyll=true`
- `.moxide.toml` in sharerr-rs: `excluded="target"`
- `.vscode/settings.json` in sharerr-rs: `rust=true`
- `.zed/settings.json` in sharerr-rs: `rust=true`
- `_config.yml` in sharerr-rs: `repo=sharerr-rs title=sharerr description=Share your media library with friends, over the tools you already run.`
