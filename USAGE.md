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
| `.github/actions/apt/lib.sh`                       |              | x          |                    | x      | x          | 3     |
| `.github/actions/fetch-latest-artifact/action.yml` |              | x          |                    | x      | x          | 3     |
| `.github/actions/mark-tree/action.yml`             |              |            |                    | x      | x          | 2     |
| `.github/actions/setup-tool/action.yml`            |              | x          |                    | x      | x          | 3     |
| `.github/actions/setup-tool/install.sh`            |              | x          |                    | x      | x          | 3     |
| `.github/actions/setup-tool/lib.sh`                |              | x          |                    | x      | x          | 3     |
| `.github/actions/setup-tools/action.yml`           |              | x          |                    | x      | x          | 3     |
| `.github/actions/setup-tools/install-missing.sh`   |              | x          |                    | x      | x          | 3     |
| `.github/actions/setup-tools/resolve.sh`           |              | x          |                    | x      | x          | 3     |
| `.github/actions/upsert-tracking-issue/action.yml` | x            | x          | x                  | x      | x          | 5     |
| `.github/allowed_signers`                          |              | x          |                    | x      | x          | 3     |
| `.github/osv-scanner.toml`                         |              | x          | x                  | x      | x          | 4     |
| `.github/package-lock.json`                        |              | x          | x                  | x      | x          | 4     |
| `.github/package.json`                             |              | x          | x                  | x      | x          | 4     |
| `.github/pull_request_template.md`                 |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/check_tool_versions.sh`           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/find_tree_run.sh`                 |              |            |                    | x      | x          | 2     |
| `.github/scripts/lib.sh`                           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/lint_workflows.sh`                |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/release_notes.sh`                 |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/scan_pinned_images.sh`            |              | x          |                    | x      | x          | 3     |
| `.github/scripts/trivy_scan.sh`                    |              | x          |                    |        | x          | 2     |
| `.github/workflows/cancel-closed-pr.yml`           |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/codeql.yml`                     |              | x          |                    | x      | x          | 3     |
| `.github/workflows/image-scan.yml`                 |              | x          |                    |        | x          | 2     |
| `.github/workflows/link-check.yml`                 |              | x          |                    | x      | x          | 3     |
| `.github/workflows/pages.yml`                      |              | x          |                    |        | x          | 2     |
| `.github/workflows/release-note.yml`               |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/scorecard.yml`                  |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/tool-versions.yml`              | x            | x          | x                  | x      | x          | 5     |
| `.github/zizmor.yml`                               |              | x          | x                  | x      | x          | 4     |
| `.gitignore`                                       | x            | x          | x                  | x      | x          | 5     |
| `.markdownlint.yaml`                               |              | x          | x                  | x      | x          | 4     |
| `.prettierrc.yaml`                                 |              | x          | x                  | x      | x          | 4     |
| `.shellcheckrc`                                    |              | x          | x                  | x      | x          | 4     |
| `.vscode/settings.json`                            | x            | x          | x                  | x      | x          | 5     |
| `LICENSE.md`                                       | x            | x          | x                  | x      | x          | 5     |
| `docs/CODE_OF_CONDUCT.md`                          | x            | x          | x                  | x      | x          | 5     |
| `lychee.toml`                                      |              | x          | x                  | x      | x          | 4     |
| **Files per repository**                           | 10           | 42         | 26                 | 41     | 44         | 44    |

## Template values

- `.gitignore` in homebrew-tap: `repo=homebrew-tap stray_files=true claude_settings=untracked`
- `.gitattributes` in instadroid: `repo=instadroid`
- `.github/ISSUE_TEMPLATE/config.yml` in instadroid: `repo=instadroid blank_issues=true doctor=scraper.py doctor`
- `.github/pull_request_template.md` in instadroid: `repo=instadroid`
- `.github/workflows/codeql.yml` in instadroid: `language=python Language=Python`
- `.github/workflows/image-scan.yml` in instadroid: `image_name=instadroid trivyignore=.trivyignore release_workflow=publish.yml`
- `.gitignore` in instadroid: `repo=instadroid images=true stray_files=true python=true jekyll=true`
- `.vscode/settings.json` in instadroid: `python=true`
- `.github/ISSUE_TEMPLATE/config.yml` in python-constricter: `repo=python-constricter blank_issues=false discussions=true`
- `.github/pull_request_template.md` in python-constricter: `repo=python-constricter`
- `.gitignore` in python-constricter: `repo=python-constricter stray_files=true claude_settings=untracked python=true`
- `.vscode/settings.json` in python-constricter: `python=true`
- `.github/ISSUE_TEMPLATE/config.yml` in say-hi: `repo=say-hi blank_issues=true discussions=true doctor=hi --doctor --json`
- `.github/pull_request_template.md` in say-hi: `repo=say-hi`
- `.gitignore` in say-hi: `repo=say-hi images=true stray_files=true`
- `.vscode/settings.json` in say-hi: `repo=say-hi`
- `.github/ISSUE_TEMPLATE/config.yml` in sharerr-rs: `repo=sharerr-rs blank_issues=true discussions=true doctor=sharerr doctor`
- `.github/pull_request_template.md` in sharerr-rs: `repo=sharerr-rs`
- `.github/workflows/codeql.yml` in sharerr-rs: `language=rust Language=Rust`
- `.github/workflows/image-scan.yml` in sharerr-rs: `repo=sharerr-rs image_name=sharerr trivyignore=docker/.trivyignore release_workflow=docker.yml`
- `.gitignore` in sharerr-rs: `repo=sharerr-rs mcp=true rust=true jekyll=true`
- `.vscode/settings.json` in sharerr-rs: `rust=true`
