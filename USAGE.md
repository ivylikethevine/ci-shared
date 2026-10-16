<!-- SPDX-License-Identifier: MIT -->

# Usage

Which repositories receive each shared file, written by
`scripts/usage.sh` from `repos/`; run it after changing a file list there.

| File                                               | homebrew-tap | instadroid | python-constricter | say-hi | sharerr-rs | Repos |
| -------------------------------------------------- | ------------ | ---------- | ------------------ | ------ | ---------- | ----- |
| `.editorconfig`                                    | x            | x          | x                  | x      | x          | 5     |
| `.github/CODEOWNERS`                               | x            | x          | x                  | x      | x          | 5     |
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
| `.github/scripts/check_tool_versions.sh`           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/find_tree_run.sh`                 |              |            |                    | x      | x          | 2     |
| `.github/scripts/lib.sh`                           | x            | x          | x                  | x      | x          | 5     |
| `.github/scripts/lint_workflows.sh`                |              | x          |                    |        | x          | 2     |
| `.github/scripts/release_notes.sh`                 |              | x          | x                  | x      | x          | 4     |
| `.github/scripts/scan_pinned_images.sh`            |              | x          |                    | x      | x          | 3     |
| `.github/scripts/trivy_scan.sh`                    |              | x          |                    |        | x          | 2     |
| `.github/workflows/cancel-closed-pr.yml`           |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/codeql.yml`                     |              | x          |                    | x      | x          | 3     |
| `.github/workflows/link-check.yml`                 |              | x          |                    | x      | x          | 3     |
| `.github/workflows/pages.yml`                      |              | x          |                    |        | x          | 2     |
| `.github/workflows/release-note.yml`               |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/scorecard.yml`                  |              | x          | x                  | x      | x          | 4     |
| `.github/workflows/tool-versions.yml`              | x            | x          | x                  | x      | x          | 5     |
| `.github/zizmor.yml`                               |              | x          | x                  | x      | x          | 4     |
| `.markdownlint.yaml`                               |              | x          |                    | x      | x          | 3     |
| `.prettierrc.yaml`                                 |              | x          |                    | x      | x          | 3     |
| `.shellcheckrc`                                    |              | x          |                    | x      | x          | 3     |
| `lychee.toml`                                      |              | x          | x                  | x      | x          | 4     |
| **Files per repository**                           | 6            | 34         | 15                 | 33     | 36         | 36    |

## Template values

- `.github/workflows/codeql.yml` in instadroid: `language=python Language=Python`
- `.github/workflows/codeql.yml` in sharerr-rs: `language=rust Language=Rust`
