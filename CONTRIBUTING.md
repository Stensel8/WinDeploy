# Contributing to WinDeploy

Thanks — small, tested PRs help most.

### Quick start
1. Fork → branch → change → PR.  
2. Test on Windows 11.

### Guidelines
- Commit: `<type>: short summary` (feat, fix, docs, style, refactor, test, chore).  
- Follow PowerShell conventions (PascalCase funcs, camelCase vars, verb-noun, comment-based help).  
- Avoid hard-coded paths; use config/variables.

### Testing
- Test on a clean Windows 11 machine.  
- Run PSScriptAnalyzer: Install-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path .\ -Recurse.  
- No syntax errors; logs show expected behavior.

### Pull requests
- Update docs if needed, include test notes and related issue references.  
- Checklist: tested, linter passed, clear description/screenshots.

### Issues
Include: short description, reproduction steps, expected vs actual, logs and env (Windows/PowerShell versions).

### Allowed / Not allowed
Welcome: bug fixes, docs, tests, small features.  
Not accepted: malware, proprietary deps, breaking changes without prior discussion.
