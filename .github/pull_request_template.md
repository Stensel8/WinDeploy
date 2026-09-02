## Summary

<!-- What does this PR do and why? -->

## Type of change

- [ ] `feat` — new feature or script
- [ ] `fix` — bug fix
- [ ] `content` — update or improve the site's landing page
- [ ] `docs` — changes to README, CONTRIBUTING, or meta documentation
- [ ] `chore` — maintenance (dependencies, config, CI/CD)
- [ ] `refactor` — restructuring without behaviour changes
- [ ] `style` — formatting, whitespace, typos
- [ ] `revert` — reverting a previous commit

> [PR title and commit types must follow these standards — view the contributing guide](https://github.com/Thectic-NL/WinDeploy/blob/main/CONTRIBUTING.md#commit-messages)

## Checklist

- [ ] PR title follows the commit convention
- [ ] Tested on a real Windows 11 25H2 machine (required for anything under `Scripts/` or `Docs/` — CI cannot exercise BitLocker, Sysprep, WinGet or Defender)
- [ ] PSScriptAnalyzer passes locally
- [ ] No hardcoded IPs, credentials, or company-specific data
- [ ] Both EN (`*.md`) and NL (`*.nl.md`) versions updated, if `src/content/` changed
- [ ] No broken internal links, if `src/` changed
- [ ] Site tested locally with `cd src && hugo server`, if `src/` changed

## Notes

<!-- Anything reviewers should know -->
