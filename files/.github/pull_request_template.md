# What's new

## What changed and why

<!-- Keep it brief, but descriptive. -->

____________ used to [be/do/say] ____________ but now it [is/does/says] ____________ because of ____________.

## Release note

<!-- One or two sentences a user reads on the release page: what they see
     differently after upgrading, present tense, no file names. Write `none`
     when nothing a user sees changes (tests, CI, doc wording). The release
     workflow collects this section into the release notes; the PR title is
     only the fallback. -->

none

## Issue and discussion links

Link any relevant issues or discussions here.

## Checklist

If one of these cannot be completed, give a justification.

<!-- shared:if repo=say-hi -->
- [ ] New code meets the 90% test coverage target (the coverage comment flags a miss; it does not block)
- [ ] All tests and CI checks green
- [ ] All calls to `sh` were tested with dash as `/bin/sh`
- [ ] Any disabled linter/code-style rule is explained
- [ ] Affected docs are updated (see CONTRIBUTING's table)
<!-- shared:endif -->
<!-- shared:if repo=sharerr-rs -->
- [ ] The verification loop in [docs/CONTRIBUTING.md](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#the-verification-loop) passes (`scripts/check.sh`; a check it reports as skipped has not passed)
- [ ] MSRV 1.98 still holds (CI's `msrv` job checks it; locally, `docker build -f docker/Dockerfile .` is the equivalent, since a newer local toolchain won't catch a breach)
- [ ] Tier-1 tests stay hermetic: no network, no containers, no database
- [ ] This adds or extends a test that would have failed without the change, if it's a new feature or a bug fix ([test policy](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#test-policy))
- [ ] No secret reaches `sharerr.toml` ([settings reference](https://github.com/ivylikethevine/__repo__/blob/main/docs/SETTINGS.md#vault-secrets))
- [ ] Affected docs are updated ([which doc changes with what](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#which-doc-changes-with-what))
<!-- shared:endif -->
<!-- shared:if repo=instadroid -->
- [ ] The checks in [docs/CONTRIBUTING.md](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#development-setup) pass locally
- [ ] New behavior or a bug fix comes with a test in `tests/`
- [ ] Coverage stays at or above the `fail_under` floor in [pyproject.toml](https://github.com/ivylikethevine/__repo__/blob/main/pyproject.toml)
- [ ] Affected docs are updated ([which docs change with what](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#which-docs-change-with-what))
<!-- shared:endif -->
<!-- shared:if repo=python-constricter -->
- [ ] CI's checks pass locally (`tests/ci_local.py`, see docs/CONTRIBUTING.md)
- [ ] New behaviour has tests; coverage stays at 100%
- [ ] Affected docs are updated (README, and docs/CHANGELOG.md for user-facing changes)
<!-- shared:endif -->

## AI disclosure

AI usage is allowed on this project, but "[agent] said _______" is not a valid excuse for problems with the final product. See [AI usage](https://github.com/ivylikethevine/__repo__/blob/main/README.md#ai-usage) and [AI-assisted contributions](https://github.com/ivylikethevine/__repo__/blob/main/docs/CONTRIBUTING.md#ai-assisted-contributions).

- [ ] (If applicable) This code was written with generative AI.
- [ ] **(If yes to above)** I have reviewed, understood, and stand behind this code as if it were entirely hand written.
