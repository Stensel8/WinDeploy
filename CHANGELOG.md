# Changelog

All notable changes to WinDeploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.7.3] - 2026-05-01

### Fixed
- Office installation no longer triggers the CDN fallback when a 32-bit version of Microsoft 365 is already installed. Pre-install detection now also checks `WOW6432Node` registry paths for 32-bit Office installations.
- Added a post-winget-failure re-check before the CDN fallback: if Office is present after winget exits with a non-zero code, the fallback is skipped entirely.
- Disabled the `Microsoft.Office` winget package — Microsoft consistently breaks their own package (exit code -1978335226, "Running ShellExecute failed") and has no clear explanation for why. Office is now installed exclusively via CDN/ODT, which is reliable.
- Microsoft Store app installs are now skipped with a single warning when the Store is unavailable (e.g. Windows Sandbox, LTSC, or policy-restricted environments). Previously, each Store app would fail individually with a `Rest API internal error`, producing noisy log output.
- Fixed PSScriptAnalyzer warning in `Deploy.ps1`: `$localPath` in `Start-Job` ScriptBlock now correctly uses the `$using:` scope modifier instead of being passed via `param`/`-ArgumentList`.

### Performance
- Converted all documentation images from PNG to AVIF (CRF 35, libaom-av1) for significantly smaller file sizes.

---

## [0.7.2] - 2026-05-01

### Fixed
- Removed unused `RegOutDef1/2/3` variable assignments in `Set-Theme.ps1` (PSScriptAnalyzer cleanup).
- Renamed `Write-Log` to `Write-PrinterLog` in archived printer scripts to avoid shadowing the built-in PowerShell cmdlet.
- Removed trailing whitespace from `Deploy.ps1`.
- Replaced non-ASCII em dash in `Start.ps1` to resolve PSScriptAnalyzer BOM warning.

### Docs
- Added `README.md` to `Scripts/Archived/` explaining the purpose of archived scripts and that printer scripts are placeholder/example code.
- Added `README.md` to `Scripts/Intune/Platform scripts/` with deployment instructions for Intune platform scripts.
- Clarified headers in `Install-NetworkPrinter.ps1` and `Uninstall-NetworkPrinter.ps1` that these are example scripts to be adapted for your own printer.

---

## [0.7.1] - 2026-04-30

### Fixed
- Application installs now explicitly pass `--source winget` and `--source msstore` to their respective install commands. Fixes "Rest API internal error" failures caused by WinGet trying all sources (including the unauthenticated msstore REST source) when no source was specified.

---

## [0.7.0] - 2026-04-30

### Added
- `SECURITY.md`. Private vulnerability disclosure via GitHub Security Advisories.
- `.github/pull_request_template.md`. PR checklist for type, testing, and no hardcoded data.
- `.github/PSScriptAnalyzerSettings.psd1`. Shared linter config for CI and local use.
- `security.yml`. Consolidated security scanning: PSScriptAnalyzer, Trivy, DevSkim, Semgrep, actionlint. All actions SHA-pinned.
- `codeql.yml`. CodeQL analysis for GitHub Actions workflows.
- `validate.yml`. PowerShell syntax check and function existence tests on every push.
- `dependency-review.yml`. Blocks HIGH and CRITICAL vulnerabilities in pull requests.
- `stale.yml`. Marks issues and PRs stale after 30 days. Closes after 14 more.

### Changed
- `Docs/autounattend.xml`. Regenerated with Schneegans unattend-generator. Desktop wallpaper and lock screen now set to `img19.jpg` (Windows default blue) via the generator's native mechanism. `GetWallpaper.ps1` writes image bytes to disk. `SetWallpaper.ps1` applies via `SystemParametersInfo` WinAPI. Lock screen uses `PersonalizationCSP`. Dark mode enabled. Generator settings URL embedded in the XML comment for easy re-editing.
- `Scripts/Start.ps1`. PowerShell 7 installer URL now resolved dynamically via GitHub API. No longer hardcoded to a specific version.
- `Scripts/Start.ps1`. `$VersionTag` parameter now correctly overrides the resolved release tag.
- `Scripts/Archived/Install-NetworkPrinter.ps1` (renamed from `Install-Konica-Minolta_C360i.ps1`). Removed hardcoded company IP, printer name, and location. All values are now required parameters. This script is an example for a Konica Minolta C360i network printer. Fork the repo and adapt it for your own device.
- `Scripts/Archived/Uninstall-NetworkPrinter.ps1` (renamed from `Uninstall-Konica-Minolta_C360i.ps1`). Same treatment. Printer name and IP are now required parameters.
- `renovate.json`. Renovate now manages `docker://` action images only. Dependabot handles `owner/repo@sha` actions.
- `dependabot.yml`. Recreated for `github-actions` ecosystem only. Updates grouped by type.
- `README.md`. Removed dead references to deleted JSON device lists. Updated CI badges. Added dependency table.

### Removed
- `powershell.yml`. Merged into `security.yml`.
- `devskim.yml`. Merged into `security.yml`.

---

## [0.6.1] - 2026-02-17

### Added
- Intune enrollment detection: Windows hardening is now skipped if the device is already enrolled in Intune.
- Dedicated section for the Windows Spotlight fix under "Windows tweaks" with user instructions and reference to Fix-Spotlight.ps1.

### Changed
- Office/M365 is no longer installed via Winget if an Office or M365 package is already detected on the system.
- Dropped support for Windows 11 24H2; only 25H2+ (build 26200+) is now supported.
- Driver lists for Dell and HP are now embedded directly in the script for improved reliability (no more external JSON files).
- Application installation output now shows both the app name and its alias/ID for improved clarity.
- Theme configuration logging/output has been cleaned up to avoid duplicate or confusing messages.
- Hostname script now provides a clear message if no serial number is found (e.g., in a VM).

### Fixed
- Improved error handling for missing serial number during hostname setup.
- Various minor improvements to logging, error handling, and user messages.

---

## [0.6.0] - 2026-02-02

### Changed
- Refactored RMM agent installation to be vendor-neutral (USB-based only).
- Updated all deployment scripts with consistent headers and improved structure.
- Cloudflare API endpoints restored and verified working.
- Cleaned up documentation and removed outdated assets.

### Fixed
- Improved script reliability after extensive internal testing.
- Various consistency improvements across the codebase.

### Removed
- Removed vendor-specific RMM integrations in favor of generic USB-based approach.

---

## [0.5.8] - 2025-11-25

### Added
- Additional documentation for Intune setup.

### Changed
- Updated dependabot config to use latest actions/checkout version.

## [0.5.7] - 2025-11-21

### Added
- Additional security messages in Harden-Windows.ps1: Can be manually enabled by the user via GUI.
- Informational links to each hardening item in Harden-Windows.ps1 output for more details.

### Changed
- Updated URLs in Harden-Windows.ps1 links to correct and more relevant sources.
- Changed the order of script execution so the RMM Agent is installed first.

### Fixed
- Bitlocker enablement issue: Sometimes Bitlocker failed to enable due to the TPM not being ready.
- Fixed an issue with RMM Agents not installing correctly. [#11](https://github.com/Stensel8/WinDeploy/issues/11)
- Fixed a rare hang where deployment would stall after detecting the RMM installer on USB. The installer was being invoked via PowerShell incorrectly which could prevent it from receiving silent switches; changed to run the installer directly and wait for completion, added longer timeouts and improved logging.

## [0.5.6] - 2025-11-20

### Added
- BitLocker enablement in Harden-Windows.ps1: Added registry policies to enable BitLocker and set XTS-AES-256 encryption, plus automated enabling on the OS drive with TPM protection and used-space-only encryption. Which is the recommended approach.

### Changed
- Enhanced bloatware removal: The Snipping Tool is no longer removed on Windows 11 systems, as it is now integrated into the core OS and provides better screenshot and video capture features compared to the legacy version.
- Updated Set-Theme.ps1: Added desktop wallpaper configuration to set "C:\Windows\Web\Wallpaper\Windows\img19.jpg" for current and default users alongside dark mode settings.

---

## [0.5.5] - 2025-11-20

### Added
- Additional fallback to CDN if Microsoft 365 apps fail to install via Winget.
- Added additional error messages during application installation to keep users informed of the process status.
- Memory integrity will now be enabled during hardening if supported by the system.
- Extra Try/Catch blocks around critical sections to improve error handling.
- Short demo GIF showcasing the deployment process added to the README.md.

### Changed
- Enhanced the startup banner to reflect session details, such as admin/non-admin status, PowerShell version (5 or 7), and Windows Terminal usage. This informs users about script execution and available controls. Also added a 15-second timer to allow cancellation if the script was launched unintentionally.

## [0.5.4] - 2025-11-19

### Added
- Additional security hardening based on CISO recommendations.
- Additional Winget exit codes to better understand installation results.

### Changed
- Merged Autorun disable options into Harden-Windows.ps1 for better maintainability and understandability.

### Fixed
- Improved handling of situations where the script was not run as admin and PowerShell 7 was not present on the system.
- Implemented PSScriptAnalyzer suggestions to enhance code quality and best practices.
- Improved GitHub API usage: Scripts now perform more attempts to obtain a good release.
- Fixed an issue where the deployment tried to use the wrong command to silently update a Dell device driver.
- Fixed an issue where the logs did not properly capture the output of Driver installs.

---

## [0.5.3] - 2025-11-18

### Fixed
- Fixed PowerShell 7 path refresh issue after installation by hardcoding `$env:ProgramFiles\PowerShell\7\pwsh.exe` to ensure correct executable usage.
- Fixed: Autounatend scripts not shown in some scenarios.

## [0.5.2] - 2025-11-18

### Added
- Added documentation images for finding Microsoft Store ID and installing via Microsoft Store

### Changed
- Changed API for GitHub Releases
- Updated README.md to improve legend
- Updated Start.ps1 script
- Updated Deploy.ps1 script

### Fixed
- Bugfixes to autologin and locales in autounattend.xml
- General bugfixes

---

## [0.5.0] - 2025-11-14

### Fixed
- Fixed bloatware removal printing duplicate messages on screen by removing redundant Write-Output calls
- Improved admin elevation handling in Start.ps1 and Deploy.ps1 to prevent script crashes when not run as administrator

### Added
- Added documentation for Intune Autopilot device preparation setup (`Docs/Intune-Autopilot-Setup.md`)
- Added RMM agent installation support with USB detection and download fallback

### Changed
- Simplified and improved project structure for better maintainability
- Streamlined deployment scripts with cleaner, more maintainable code
- Updated README.md with comprehensive documentation and updated flowchart
- Reorganized scripts into `Scripts/Deployment/` for better organization

### Removed
- Removed complex modular architecture in favor of inline scripts
- Removed unused utility modules and scripts

### Fixed
- Improved error handling and logging across all scripts
- Enhanced compatibility and reliability of deployment process

---

## [0.1.2] - 2025-10-22

### Changed
- Enhanced startup banner with script source detection and color-coded execution info
- Standardized script headers and documentation blocks for consistency
- Optimized WinGet preparation and application installation process
- Improved output formatting for Windows updates

### Fixed
- Added error logging to catch blocks and improved error messages
- Increased resiliency in bloatware removal and application installation
- `Install-WindowsUpdates.ps1`: Removed unused parameter

### Removed
- Removed all author, company, and version metadata from individual script files
- Removed redundant `.LINK` sections from documentation blocks
- Removed verbose bullet lists and "Features:" sections from descriptions

---

## [0.1.1] - 2025-10-21

### Initial Public Release

First open-source release of WinDeploy - Windows Deployment Automation Toolkit. This is the first release under the new name and repository.

---


[0.7.3]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.7.3
[0.7.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.7.2
[0.7.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.7.1
[0.7.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.7.0
[0.6.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.6.1
[0.6.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.6.0
[0.5.5]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.5
[0.5.4]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.4
[0.5.3]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.3
[0.5.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.2
[0.5.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.0
[0.1.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.2
[0.1.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.1
