# ci-shared

The one source for the CI files several repositories carry byte-identical:
composite actions, helper scripts, lint configs, the Markdown tool lockfile and
a few workflows. Each repository keeps its own copy, so local runs, editors,
Scorecard and zizmor see ordinary files; nothing in a target refers back here.
[USAGE.md](USAGE.md) lists which repositories receive each file.

## Layout

| Path                     | Holds                                                                    |
| ------------------------ | ------------------------------------------------------------------------ |
| `files/`                 | the master copies, at the path they have in a target                     |
| `repos.txt`              | each target, `owner/name` and the branch sync pull requests go to        |
| `targets/<name>.txt`     | the paths from `files/` that target receives                             |
| `USAGE.md`               | each file against the repositories receiving it, written from `targets/` |
| `scripts/check.sh`       | the shipped checks, run over this repository and `files/`                |
| `scripts/usage.sh`       | writes `USAGE.md`; `--check` fails when it is stale                      |
| `scripts/census.sh`      | groups the CI files local checkouts share by content, to find drift      |
| `scripts/sync_local.sh`  | copies `files/` into the checkouts beside this one                       |
| `scripts/sync_remote.sh` | opens or updates a pull request per target through the GitHub API        |
| `.github/workflows/`     | `sync.yml`, `checks.yml` and `tool-versions.yml`                         |

A file belongs here once two targets hold it byte-identical. Per-repository
files stay in their repository: `setup-tool/tools.txt`,
`check_tool_versions.local.sh`, `dependabot.yml`, the issue and PR templates,
and every workflow that differs.

## Changing a shared file

1. Edit it under `files/`. To share a new file, copy it in, add its path to
   each `targets/<name>.txt` that should receive it, and run
   `scripts/usage.sh`.
2. Run `scripts/check.sh`.
3. `scripts/sync_local.sh --check` lists the checkouts that differ;
   `scripts/sync_local.sh` copies the change into them, leaving any path with
   uncommitted changes alone.
4. Once this repository is on GitHub, a push to `main` opens one pull request
   per target on branch `ci-sync`, and re-pushes update it.

`scripts/census.sh --drift` lists every CI path whose copies disagree across
the checkouts, shared here or not.

## Templates

A file that differs between targets only by a few values is a template. Its
copy in `files/` spells a value `__key__` and marks lines kept only when a key
is set (`# shared:if key`) or unset (`# shared:unless key`), up to
`# shared:endif`. A target's row sets the values after the path:

```text
.github/workflows/codeql.yml language=rust Language=Rust
```

Every script renders before comparing or copying, so a target never sees a
marker, and `scripts/check.sh` lints each workflow template as every target
receives it. Values cannot hold spaces.

## To do

- python-constricter keeps its own `.markdownlint.yaml` and `.prettierrc.yaml`
  (prettier rewraps prose at 100, MD013 at 100). Move it to the shared
  hand-wrapped copies, whose checks its docs already pass unchanged, and make
  their comments generic first: they name Zed, `.moxide.toml` and
  `_config.yml`, which python-constricter does not have. Until then, prettier
  at its `printWidth: 100` rewraps the shared workflows it receives; its CI
  runs prettier over Markdown alone, so only an editor's format-on-save shows
  it.

## Checking this repository

This repository runs the checks it ships, on itself and on `files/`. The lint
configs at the root, `.github/zizmor.yml`, `.github/package.json` and its lock,
and the helpers under `.github/actions/` and `.github/scripts/` are symlinks
into `files/`, so there is one copy of each. Two files are this repository's
own: `.github/actions/setup-tool/tools.txt` pins the lint tools, and
`.github/scripts/check_tool_versions.local.sh` points the version check at the
Markdown tools' manifest and adds a second run over `files/`.

- `scripts/check.sh` runs shellcheck, shfmt, actionlint, `lint_workflows.sh`,
  zizmor, prettier,
  markdownlint and `scripts/usage.sh --check`; `checks.yml` runs it on every
  push and pull request. Locally it needs the `tools.txt` pins on `PATH` and
  `npm ci --prefix .github` once.
- `.github/scripts/check_tool_versions.sh` reports every pin behind the newest
  release past the cooldown; `tool-versions.yml` runs it weekly.

## The sync token

`sync.yml` reads `SYNC_TOKEN`, a repository secret (_Settings → Secrets and
variables → Actions → New repository secret_), holding a fine-grained personal
access token:

- **Repository access:** only the repositories in `repos.txt`.
- **Permissions:** Contents read and write (a pull request needs its branch
  pushed), Pull requests read and write; Metadata read is added automatically.
- **Expiry:** the shortest you will renew; an expired token fails the run with
  a 401.

Contents write lets the token push any branch, not just `ci-sync`. A ruleset on
each target's `main` and `dev` that requires a pull request keeps it off the
branches that matter. The bot's commits are unsigned; a target that requires
signed commits takes the pull request as a squash merge, which GitHub signs.
