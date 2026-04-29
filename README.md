# WinDeploy - Windows Deployment Automation

**Open-source Windows 11 deployment automation toolkit built with PowerShell 7**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7.0+](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows 11 25H2](https://img.shields.io/badge/Windows-11_25H2-0078D6.svg)](https://www.microsoft.com/windows)

[![Security scanning](https://github.com/Stensel8/WinDeploy/actions/workflows/security.yml/badge.svg)](https://github.com/Stensel8/WinDeploy/actions/workflows/security.yml)
[![Validate scripts](https://github.com/Stensel8/WinDeploy/actions/workflows/validate.yml/badge.svg)](https://github.com/Stensel8/WinDeploy/actions/workflows/validate.yml)
[![CodeQL](https://github.com/Stensel8/WinDeploy/actions/workflows/codeql.yml/badge.svg)](https://github.com/Stensel8/WinDeploy/actions/workflows/codeql.yml)
[![Dependabot Updates](https://github.com/Stensel8/WinDeploy/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Stensel8/WinDeploy/actions/workflows/dependabot/dependabot-updates)

Zero-touch Windows deployment with automatic driver updates, application installation, bloatware removal, and system configuration. Deploy via USB, network, RMM agents, or AutoUnattend.xml.

## Deployment options

| Local USB / AutoUnattend.xml | Intune / Autopilot |
|---|---|
| Deploy locally via USB, [`autounattend.xml`](Docs/autounattend.xml), or [one-liner script](#quick-start). | Deploy via [Intune Autopilot](Docs/Intune-Autopilot-Setup.md), targeting specific user groups. |
| [![Get started - Local](https://img.shields.io/badge/Get%20started-Local-blue?style=for-the-badge)](#quick-start) | [![Get started - Intune](https://img.shields.io/badge/Get%20started-Intune-brightgreen?style=for-the-badge)](Docs/Intune-Autopilot-Setup.md) |

<details open>
<summary>View deployment screenshots</summary>

<br>

| Deployment Start | Successful Completion |
|-----------------|----------------------|
| <img src="Docs/Deployment_Flow.png" alt="Deployment start" width="400" height="225"> | <img src="Docs/Deployment_Success.png" alt="Deployment success" width="400" height="225"> |

</details>

---

## Quick Start

**Prerequisites:** Windows 11 Pro 25H2+, PowerShell 7, internet connection

### Option 1: USB Deployment (Fresh installs)
1. Create bootable Windows 11 USB
2. Copy `autounattend.xml` to USB root
3. (Optional) Copy RMM agent as `Agent.exe` to USB root
4. Boot from USB with network connected — keep USB connected until deployment completes
5. Wait — everything happens automatically

### Option 2: Direct Execution
```powershell
# Run as Administrator in PowerShell 7
iex (irm "https://raw.githubusercontent.com/Stensel8/WinDeploy/$((irm https://api.github.com/repos/Stensel8/WinDeploy/releases/latest).tag_name)/Scripts/Start.ps1")
```

### Option 3: One-liner
```powershell
# Run as Administrator in PowerShell 7
iex (irm windeploy.stensel.nl)
```

---

## How It Works

```mermaid
graph TD
    A[Start.ps1] --> B{Admin Rights?}
    B -->|No| C[Auto-Elevate]
    C --> D{PowerShell 7?}
    B -->|Yes| D
    D -->|No| E[Install PS7 + WinGet]
    E --> F[Relaunch in PS7]
    D -->|Yes| G[Download Deploy.ps1]
    F --> G
    G --> H[Launch Deploy.ps1]
    H --> I[Install RMM Agent]
    I --> J[Update Drivers]
    J --> K[Windows Hardening]
    K --> L[Install Applications]
    L --> M[Remove Bloatware]
    M --> N[Apply Theme]
    N --> O[Set Hostname]
    O --> P[Install Windows Updates]
    P --> Q[Complete]
```

`Start.ps1` ensures PowerShell 7 and WinGet are available, handles elevation, and downloads `Deploy.ps1`. `Deploy.ps1` orchestrates the deployment by downloading and executing each script in sequence.

---

## Configuration

### Customize Application List
Edit [`Scripts/Deployment/Install-Applications.ps1`](Scripts/Deployment/Install-Applications.ps1) (lines 20–30):
```powershell
$Applications = @(
    "Microsoft.VCRedist.2015+.x64",
    "Microsoft.Office",
    "Microsoft.Teams",
    # Add your apps here
)
```

### Customize Bloatware List
Edit [`Scripts/Deployment/Remove-Bloat.ps1`](Scripts/Deployment/Remove-Bloat.ps1) (lines 15–40):
```powershell
$BloatwareList = @(
    "Microsoft.BingNews",
    "Microsoft.GamingApp",
    # Add packages to remove
)
```

### Configure RMM Agent Installation
Place your agent installer as `Agent.exe` (or any `*agent*.exe`) on the USB drive root. The script detects and installs it silently during deployment. Works with any RMM solution that supports silent installation (e.g., `/S` switch).

### Supported Devices (Drivers & Firmware)
- **Dell**: Latitude, OptiPlex, Precision, XPS series
- **HP**: EliteBook, ProBook, EliteDesk, ProDesk, ZBook series

---

## Logging

All operations are logged to `C:\WinDeploy\Logs\`:
- `Start.log` — main entry point log
- `Install-Drivers.log`, `Install-Applications.log`, etc. — per-script logs

View logs in real-time:
```powershell
Get-Content "C:\WinDeploy\Logs\Start.log" -Wait -Tail 20
```

---

## Dependencies

WinDeploy automatically installs and manages all dependencies:

| Dependency | Source | Purpose |
|---|---|---|
| [winget-install](https://www.powershellgallery.com/packages/winget-install) | PowerShell Gallery | Reliable WinGet installation by [asheroto](https://github.com/asheroto/winget-install) |
| [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate) | PowerShell Gallery | Windows Update automation |
| [Dell Command Update](https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update) | WinGet | Dell driver management |
| [HP Image Assistant](https://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html) | WinGet | HP driver management |

---

## Troubleshooting

**Script blocked by execution policy**
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

**Windows Spotlight not working after deployment**
```powershell
# Run as Administrator
& "C:\WinDeploy\Download\Fix-Spotlight.ps1"
```
Then set lock screen to "Windows Spotlight" in Settings > Personalization > Lock screen.

**WinGet not found**
```powershell
# Run as Administrator
Install-Script winget-install -Force
winget-install
```

**Drivers not installing**
- Confirm internet connection
- Check device is a supported Dell or HP model
- Review `C:\WinDeploy\Logs\Install-Drivers.log`

**Applications failing to install**
- Run `winget --version` to verify WinGet works
- Use `winget search <app-name>` to verify the correct package ID
- Check `C:\WinDeploy\Logs\Install-Applications.log`
- If default ID fails, try the `msstore` source version:
  1. Run `winget search <app-name>`
  2. Find entries with `Source: msstore`
  3. Or find the App ID at [apps.microsoft.com](https://apps.microsoft.com)

![Finding the msstore App ID](Docs/Finding-msstore-id.png)

---

## Credits

- [PowerShell](https://github.com/PowerShell/PowerShell)
- [WinGet](https://github.com/microsoft/winget-cli)
- [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate)
- [winget-install](https://www.powershellgallery.com/packages/winget-install) by [asheroto](https://github.com/asheroto/winget-install)
- [Dell Command Update](https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update)
- [HP Image Assistant](https://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html) / [HP CMSL](https://developers.hp.com/hp-client-management/doc/client-management-script-library)

## Contributing & Support

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

- **Issues**: [GitHub Issues](https://github.com/Stensel8/WinDeploy/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Stensel8/WinDeploy/discussions)

## Disclaimer

Provided "as is" without warranty. Test in a safe environment before production use.

---
