param(
    [string]$VersionTag
)

# Helper: find or install PowerShell 7 robustly
function Ensure-Pwsh7 {
    $pwshPath = $null
    $pwshPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    foreach ($path in $pwshPaths) {
        if (Test-Path $path) { $pwshPath = $path; break }
    }
    if ($pwshPath) { return $pwshPath }

    # Try winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
        } catch {}
        foreach ($path in $pwshPaths) { if (Test-Path $path) { $pwshPath = $path; break } }
    }
    # Fallback MSI
    if (-not $pwshPath) {
        try { Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -UseMSI -Quiet" } catch {}
        foreach ($path in $pwshPaths) { if (Test-Path $path) { $pwshPath = $path; break } }
    }
    if ($pwshPath) { return $pwshPath }
    Write-Host "Failed to install PowerShell 7, install manually." -ForegroundColor Red
    exit 1
}

# Helper: ensure WinGet present (optional, since deploy.ps1 may use it)
function Ensure-WinGet {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    $temp = [System.IO.Path]::GetTempFileName() + ".ps1"
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1' -OutFile $temp -UseBasicParsing
        Start-Process pwsh -Wait -NoNewWindow -ArgumentList "-ExecutionPolicy Bypass -File `"$temp`""
        Remove-Item $temp -Force
    } catch {}
}

# Elevate if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psz = Ensure-Pwsh7
    $args = ""
    if ($VersionTag) { $args = "-VersionTag '$VersionTag'" }
    Start-Process -FilePath $psz -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`" $args" -Verb RunAs
    exit
}

$psz = Ensure-Pwsh7
Ensure-WinGet

# Download deploy.ps1 (always overwrite)
$deployPath = "C:\WinDeploy\Deploy.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/main/Scripts/Deploy.ps1" -OutFile $deployPath -UseBasicParsing -ErrorAction Stop

# Re-launch deployment in PowerShell 7 (always, so deployment logic can be simple)
Start-Process -FilePath $psz -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$deployPath`"" -Wait
