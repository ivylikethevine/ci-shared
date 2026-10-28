# Security Policy

This repository is the one source of the CI files several repositories carry:
a change to `files/` reaches every target through its sync pull request. A
flaw in a shared workflow, action or script is therefore a flaw in all of
them, and the sync itself mints a write token per target from its GitHub App.

## In scope

- Anything under `files/`: workflows, composite actions, helper scripts, lint
  configs and the Markdown tools' lock, as the targets receive them.
- The sync: `sync.yml`, `scripts/sync_remote.sh` and the scripts it calls,
  including how they handle the App's key, the per-target tokens and the
  signing key.
- This repository's own workflows and the rulesets in `rulesets/`.

A flaw in a target's own code belongs to that repository's security policy.

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Report it privately
through
[GitHub private vulnerability reporting](https://github.com/ivylikethevine/ci-shared/security/advisories/new).

- **Acknowledgement within 14 days**, usually much sooner: this is a
  one-maintainer repository, and the report reaches that maintainer directly.
- **Coordinated disclosure.** A confirmed vulnerability is fixed here, and the
  fix synced to every target, before it is discussed publicly, unless the
  reporter and maintainer agree otherwise.
- **Advisories are public.** Every fixed vulnerability gets a GitHub Security
  Advisory naming the affected files and the fix.
- **Credit.** Reporters are credited in the advisory unless they ask not to
  be.
