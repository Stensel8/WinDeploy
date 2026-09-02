# Contributing to WinDeploy

Thanks. Small, tested PRs help most.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

**Format:**
```
<type>: <short description>
```

**Types:**

| Type | When to use |
|------|-------------|
| `feat` | New feature or script |
| `fix` | Bug fix |
| `content` | Update or improve the site's landing page content |
| `docs` | Changes to README, CONTRIBUTING, or other meta files |
| `chore` | Maintenance — dependencies, config, CI/CD |
| `refactor` | Restructure without changing behaviour |
| `style` | Formatting, whitespace, typo fixes |
| `revert` | Reverting a previous commit |

**Rules:**
- Use lowercase for the type and description
- Keep the subject line under 72 characters
- No period at the end
- Use the imperative mood ("add", "fix", "update" — not "added", "fixed")

## PowerShell conventions

- PascalCase functions, camelCase variables, `Verb-Noun` naming, comment-based help
- Avoid hard-coded paths; use config/variables
- Run PSScriptAnalyzer before opening a PR: `Install-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path .\ -Recurse -Settings .github/PSScriptAnalyzerSettings.psd1`

## Testing

- **Test on a real Windows 11 25H2 machine.** Nothing here runs in CI — GitHub-hosted runners can't exercise BitLocker, TPM, Sysprep, WinGet installs or Defender ASR — so this is the only way a change is actually verified.
- No syntax errors; logs in `C:\WinDeploy\Logs\` show the expected behaviour.

## Pull requests

- PR titles follow the commit convention above
- One logical change per PR
- If you touch `src/content/`, update both EN (`*.md`) and NL (`*.nl.md`) versions
- Test the site locally with `cd src && hugo server` before opening a PR that touches `src/`

## Project layout

```
Scripts/                 Deployment scripts (Start.ps1, Deploy.ps1, Scripts/Deployment/*)
Docs/                    autounattend.xml and Intune setup docs
src/                     The Hugo site (windeploy.thectic.nl) — landing page only.
                         Scripts/ and Docs/ are NOT duplicated here; the site
                         links to GitHub Releases, which stays the source of
                         truth for what actually gets deployed.
  src/content/           Landing page content (_index.md EN, _index.nl.md NL)
  src/layouts/            Template overrides on top of the Hextra theme
  src/hugo.toml           Site configuration
```

The site is built and deployed to Bunny.net from `.github/workflows/deploy-bunny.yml` on every push to `main` that touches `src/`. It is bilingual (EN + NL); keep structure and headings in sync between the two versions of a page.

## Issues

Include: short description, reproduction steps, expected vs actual, logs and environment (Windows/PowerShell versions).

## Allowed / not allowed

Welcome: bug fixes, docs, tests, small features.
Not accepted: malware, proprietary dependencies, breaking changes without prior discussion.
