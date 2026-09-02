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
  Zero-touch Windows 11-deployment: drivers, applicaties, bloatware verwijderen, security hardening en BitLocker
{{< /hextra/hero-subtitle >}}
</div>

<div class="hx-mb-10" style="margin-top: 2.5rem !important;">
{{< hextra/hero-badge link="https://github.com/THectic-NL/WinDeploy#quick-start" >}}
  <span>Snel starten</span>
  {{< icon name="arrow-right" attributes="height=20" >}}
{{< /hextra/hero-badge >}}
{{< hextra/hero-badge link="https://github.com/THectic-NL/WinDeploy" >}}
  <span>Bekijk op GitHub</span>
  {{< icon name="github" attributes="height=20" >}}
{{< /hextra/hero-badge >}}
</div>

<div class="hx-mt-6"></div>

## Uitvoeren

Als Administrator, in PowerShell 7:

```powershell
iex (irm "https://raw.githubusercontent.com/THectic-NL/WinDeploy/$((irm https://api.github.com/repos/THectic-NL/WinDeploy/releases/latest).tag_name)/Scripts/Start.ps1")
```

`Start.ps1` elevate't indien nodig, installeert PowerShell 7 en WinGet als die ontbreken, en geeft daarna door aan `Deploy.ps1`, dat elke deploymentstap van die release na elkaar downloadt en uitvoert.

{{< callout type="info" >}}
Elke run staat vast op één GitHub release tag, van begin tot eind. Een deployment die start tegen `v0.9.0` blijft de scripts van `v0.9.0` gebruiken, ook als `main` tijdens de run verandert.

Voor USB/offline installaties via `autounattend.xml`, en de volledige configuratiereferentie, zie de [GitHub-repository](https://github.com/THectic-NL/WinDeploy).
{{< /callout >}}

## Wat het doet

| Stap | |
|---|---|
| RMM-agent | Installeert een monitoring agent vanaf een USB-stick, indien aanwezig |
| Drivers | Dell Command Update of HP Client Management, gedetecteerd op model |
| Hardening | SMB signing, LSA-protection, HVCI, Defender ASR-regels, schermvergrendeling — zie hieronder |
| Applicaties | WinGet + Microsoft 365 via CDN/ODT |
| Bloatware verwijderen | Verwijdert consumer-apps, blokkeert herinstallatie via policy |
| Tweaks *(optioneel)* | Een [WinUtil](https://github.com/ChrisTitusTech/winutil)-preset, achter een Y/N-prompt |
| Thema, hostnaam | Dark mode, `PC-<serienummer>`-naamgeving |
| Windows Update | Installeert alles wat beschikbaar is |

Twee stappen vragen eerst om bevestiging: **BitLocker** en de **WinUtil-tweaks**. Beide lopen na 90 seconden af en kiezen dan standaard nee, zodat een onbeheerde run nooit vastloopt. Geef `-NonInteractive` mee om beide direct over te slaan.

## Security hardening

Automatisch toegepast: SMBv1 verwijderd, SMB signing verplicht, onveilige guest-logons geblokkeerd, LSA-protection (RunAsPPL), WDigest plaintext-credentialcaching uitgeschakeld, anonieme SAM/share-enumeratie beperkt, LLMNR uitgeschakeld, memory integrity (HVCI), 9 Defender Attack Surface Reduction-regels, AutoRun uitgeschakeld, beveiligde schermvergrendeling.

BitLocker versleutelt, na bevestiging, `C:` met XTS-AES-256, maakt een recovery password aan, slaat dit op in de Documenten-map van de operator en toont het op het scherm.

## Met dank aan

Gebouwd op [PowerShell](https://github.com/PowerShell/PowerShell), [WinGet](https://github.com/microsoft/winget-cli), [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate), [winget-install](https://github.com/asheroto/winget-install) van asheroto, en — voor de optionele tweaks-stap — [WinUtil](https://github.com/ChrisTitusTech/winutil) van Chris Titus.
