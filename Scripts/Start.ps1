param(
    [string]$VersionTag
)

# Helper: find or install PowerShell 7 robustly
function Install-Pwsh7 {
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
function Install-WinGet {
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
    $psz = Install-Pwsh7
    $versionArgs = ""
    if ($VersionTag) { $versionArgs = "-VersionTag '$VersionTag'" }
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        # Script is run via iex, download to temp file
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/main/Scripts/Start.ps1" -OutFile $scriptPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Failed to download Start.ps1 for elevation: $_" -ForegroundColor Red
            exit 1
        }
    }
    Start-Process -FilePath $psz -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" $versionArgs" -Verb RunAs
    exit
}

Set-Location $PSScriptRoot
Write-Output "Elevated to administrator, starting WinDeploy setup."

# Start logging
$logDir = "C:\WinDeploy\Logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "Start.log"
Start-Transcript -Path $logFile -Append -NoClobber

$psz = Install-Pwsh7
Install-WinGet

# Ensure directories exist
$deployDir = "C:\WinDeploy\Download"
$logDir = "C:\WinDeploy\Logs"
if (!(Test-Path $deployDir)) { New-Item -ItemType Directory -Path $deployDir -Force | Out-Null }
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Download or copy deploy.ps1
$deployPath = Join-Path $deployDir "Deploy.ps1"
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/main/Scripts/Deploy.ps1" -OutFile $deployPath -UseBasicParsing -ErrorAction Stop
    Write-Output "Downloaded Deploy.ps1 to $deployPath"
} catch {
    # If download fails, use local copy if available
    $localDeployPath = Join-Path $PSScriptRoot "Deploy.ps1"
    if (Test-Path $localDeployPath) {
        Copy-Item $localDeployPath $deployPath -Force
        Write-Output "Copied local Deploy.ps1 to $deployPath"
    } else {
        $errorMsg = "Cannot download or find Deploy.ps1: $_"
        Write-Output $errorMsg
        throw $errorMsg
    }
}

# Re-launch deployment in PowerShell 7 (always, so deployment logic can be simple)
Write-Output "Starting Deploy.ps1 with PowerShell 7"
Start-Process -FilePath $psz -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$deployPath`"" -Wait
Stop-Transcript
