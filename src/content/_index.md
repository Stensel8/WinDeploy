---
title: ""
toc: false
---

<div class="hx-mt-6 hx-mb-6">
{{< hextra/hero-headline >}}
  WinDeploy
{{< /hextra/hero-headline >}}
</div>

<div class="hx-mb-12">
{{< hextra/hero-subtitle >}}
  Zero-touch Windows 11 deployment: drivers, applications, bloatware removal, security hardening and BitLocker
{{< /hextra/hero-subtitle >}}
</div>

<div class="hx-mb-10" style="margin-top: 2.5rem !important;">
{{< hextra/hero-badge link="https://github.com/Thectic-NL/WinDeploy#quick-start" >}}
  <span>Quick start</span>
  {{< icon name="arrow-right" attributes="height=20" >}}
{{< /hextra/hero-badge >}}
{{< hextra/hero-badge link="https://github.com/Thectic-NL/WinDeploy" >}}
  <span>View on GitHub</span>
  {{< icon name="github" attributes="height=20" >}}
{{< /hextra/hero-badge >}}
</div>

<div class="hx-mt-6"></div>

## Run it

As Administrator, in PowerShell 7:

```powershell
iex (irm "https://raw.githubusercontent.com/Thectic-NL/WinDeploy/$((irm https://api.github.com/repos/Thectic-NL/WinDeploy/releases/latest).tag_name)/Scripts/Start.ps1")
```

`Start.ps1` elevates if needed, installs PowerShell 7 and WinGet if they are missing, then hands off to `Deploy.ps1`, which downloads and runs each deployment step from that release in sequence.

{{< callout type="info" >}}
Every run is pinned to one GitHub release tag, start to finish. A deployment that starts against `v0.9.0` keeps using `v0.9.0`'s scripts even if `main` changes mid-run.

For USB / offline installs via `autounattend.xml`, and the full configuration reference, see the [GitHub repository](https://github.com/Thectic-NL/WinDeploy).
{{< /callout >}}

## What it does

| Step | |
|---|---|
| RMM agent | Installs a monitoring agent from a USB drive, if present |
| Drivers | Dell Command Update or HP Client Management, model-detected |
| Hardening | SMB signing, LSA protection, HVCI, Defender ASR rules, screen lock — see below |
| Applications | WinGet + Microsoft 365 via CDN/ODT |
| Bloatware removal | Removes consumer apps, blocks their reinstall via policy |
| Tweaks *(opt-in)* | A [WinUtil](https://github.com/ChrisTitusTech/winutil) preset, behind a Y/N prompt |
| Theme, hostname | Dark mode, `PC-<serial>` naming |
| Windows Update | Installs everything available |

Two steps ask before they run: **BitLocker** and the **WinUtil tweaks**. Both time out after 90 seconds and default to no, so an unattended run never stalls. Pass `-NonInteractive` to skip both outright.

## Security hardening

Applied automatically: SMBv1 removed, SMB signing required, insecure guest logons blocked, LSA protection (RunAsPPL), WDigest plaintext credential caching disabled, anonymous SAM/share enumeration restricted, LLMNR disabled, memory integrity (HVCI), 9 Defender Attack Surface Reduction rules, AutoRun disabled, secure screen lock.

BitLocker, on confirmation, encrypts `C:` with XTS-AES-256, creates a recovery password, saves it to the operator's Documents folder and prints it on screen.

## Credits

Built on [PowerShell](https://github.com/PowerShell/PowerShell), [WinGet](https://github.com/microsoft/winget-cli), [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate), [winget-install](https://github.com/asheroto/winget-install) by asheroto, and — for the optional tweaks step — [WinUtil](https://github.com/ChrisTitusTech/winutil) by Chris Titus.
