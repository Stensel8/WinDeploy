# Changelog

All notable changes to WinDeploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.5.0] - 2025-11-14

### Added
- Reorganized project structure with scripts moved to `Scripts/Deployment/` folder
- Enhanced `Start.ps1` to handle version resolution, PS7 installation, and deployment orchestration
- Added `Scripts/Deployment/Set-HostName.ps1` for hostname configuration (optional)
- Improved error handling and logging throughout
- Added script to bypass OOBE privacy settings during Autopilot (`Scripts\Intune\Platform scripts\Skip-OOBEPrivacy-Intune.ps1`)

### Changed
- **BREAKING**: Removed modular architecture; all scripts now contain inline code instead of using utility modules
- **BREAKING**: Removed `Deploy-Device.ps1` orchestrator; functionality integrated into `Start.ps1`
- Simplified deployment scripts for better maintainability
- Updated README.md with new project structure and deployment flow

### Removed
- Removed RMM Agent installation from deployment flow
- Removed Intune Autopilot hash generation from deployment flow
- Removed all utility modules (`Scripts/Utilities/*.psm1`)
- Removed various utility scripts no longer needed in the streamlined version
- 

### Fixed
- Improved compatibility and reliability of deployment scripts
- Improved deployment speed by changing the order of scripts

---

## [0.1.2] - 2025-10-22

### Changed
- Enhanced startup banner to display script source (local file path, GitHub URL, or remote execution)
- Improved script path detection for remote execution via `irm | iex`
- Fixed display of execution method with color-coded source information
- Standardized all script headers for consistency across the codebase
- Streamlined documentation blocks (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`) for clarity
- Renamed `Test-AdminPrivileges` to `Test-AdminPrivilege` (singular noun) in `Install-PowerShell7.ps1` and `Install-Winget.ps1`
- Added a warning when importing drivers via `Import-Drivers.ps1`.
- Start `WinGet` preparation earlier in `Start.ps1` (ensures dependencies VCLibs/UI.Xaml/VCRedist are ready once, avoids duplicate checks later)
- `Install-Applications.ps1`: rely on early WinGet prep, only report status instead of re-installing dependencies
- `Install-WindowsUpdates.ps1`: user-facing output now shows status and update title on the same line for clarity

### Fixed
- Added error logging to empty catch blocks in `Start.ps1` (fixes #2)
- Improved error messages in path resolution catch blocks
- `Install-Applications.ps1`: Added interactive fallback for WinGet hash mismatch to download via BITS and run installer; logs URL in non-interactive mode
- `Remove-Bloat.ps1`: Increased resiliency (continue-on-error, fixed some bugs)
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

[0.5.0]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.5.0
[0.1.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.2
[0.1.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.1
