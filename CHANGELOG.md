# Changelog

All notable changes to WinDeploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.5.3]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.3
[0.5.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.2
[0.5.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.0
[0.1.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.2
[0.1.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.1
