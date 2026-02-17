# Changelog

All notable changes to WinDeploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.6.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.6.0
[0.5.5]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.5
[0.5.4]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.4
[0.5.3]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.3
[0.5.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.2
[0.5.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.0
[0.1.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.2
[0.1.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.1
