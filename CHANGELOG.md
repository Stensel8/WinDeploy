# Changelog

All notable changes to WinDeploy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

### Fixed
- Added error logging to empty catch blocks in `Start.ps1` (fixes #2)
- Improved error messages in path resolution catch blocks

### Removed
- Removed all author, company, and version metadata from individual script files
- Removed redundant `.LINK` sections from documentation blocks
- Removed verbose bullet lists and "Features:" sections from descriptions

---

## [0.1.1] - 2025-10-21

### Initial Public Release

First open-source release of WinDeploy - Windows Deployment Automation Toolkit. This is the first release under the new name and repository.

---

[0.1.2]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.2
[0.1.1]: https://github.com/Stensel8/WinDeploy/releases/tag/v0.1.1
