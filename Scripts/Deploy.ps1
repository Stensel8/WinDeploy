Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Fetch the latest release tag for downloading scripts
$releaseTag = $null
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Stensel8/WinDeploy/releases/latest" -ErrorAction SilentlyContinue
    if ($latestRelease.tag_name) {
        $releaseTag = $latestRelease.tag_name
    }
} catch {
    # Ignore
}
if (!$releaseTag) {
    Write-DeployLog "Failed to fetch latest release tag. Cannot proceed." -IsError
    exit 1
}

# Read version
$version = $null
try {
    $version = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/VERSION" -ErrorAction SilentlyContinue
    $version = $version.Trim()
} catch {
    # Ignore
}

# Print header
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                    WinDeploy Deployment" -ForegroundColor Yellow
Write-Host "            Windows Deployment Automation Toolkit" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
if ($version) {
    Write-Host "Version: $version" -ForegroundColor Green
}
Write-Host ""

Function Write-DeployLog {
    param(
        [string]$Message,
        [switch]$IsError
    )

    try {
        $logDir = "C:\WinDeploy\Logs"
        if (!(Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $scriptName = if ($MyInvocation.ScriptName) {
            [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
        } else {
            "WinDeploy"
        }

        $logFile = Join-Path $logDir "$scriptName.log"
        $Message | Out-File -FilePath $logFile -Append -ErrorAction Stop
    } catch {
        # Ignore logging errors to prevent script failure
    }

    if ($IsError) {
        # Avoid noisy error records and stack traces in the console
        Write-Warning $Message
    } else {
        Write-Output $Message
    }
}

function Get-ScriptDisplay {
    if ($PSCommandPath) { return "Script: $PSCommandPath" }
    if ($PSScriptRoot)   { return "Directory: $PSScriptRoot" }
    return "Execution: In-memory (no script path) - Launched via Start.ps1"
}

# Banner
Write-Output ""
Write-Output "    ============================================================"
Write-Output "                    WinDeploy Deployment                        "
Write-Output "            Windows Deployment Automation Toolkit               "
Write-Output "    ============================================================"
Write-Output ""
Write-Output "    PowerShell: $($PSVersionTable.PSVersion)"
Write-Output ("    {0}" -f (Get-ScriptDisplay))
Write-Output ""

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "ERROR: This script must be run as administrator."
    exit 1
}

# Define deployment steps (customize as needed)
$deploymentSteps = @(
    @{ Name = "Driver Installation";        ScriptName = "Install-Drivers.ps1" }
    @{ Name = "RMM Agent Installation";     ScriptName = "Install-RMMAgent.ps1" }
    @{ Name = "AutoRun Disable";            ScriptName = "Disable-AutoRun.ps1" }
    @{ Name = "Application Installation";   ScriptName = "Install-Applications.ps1" }
    @{ Name = "Bloatware Removal";          ScriptName = "Remove-Bloat.ps1" }
    @{ Name = "Theme Configuration";        ScriptName = "Set-Theme.ps1" }
    @{ Name = "Hostname Configuration";     ScriptName = "Set-HostName.ps1" }
    @{ Name = "Windows Updates";            ScriptName = "Install-WindowsUpdates.ps1" }
)

$dlRoot = "C:\WinDeploy\Download"
if (!(Test-Path $dlRoot)) { New-Item -Type Directory -Path $dlRoot | Out-Null }

$allSuccessful = $true

foreach ($step in $deploymentSteps) {
    Write-Output ""
    Write-Output "======================================== "
    Write-Output "  $($step.Name)"
    Write-Output "======================================== "
    Write-Output ""
    $localPath = Join-Path $dlRoot $step.ScriptName
    $scriptAvailable = $false
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/Scripts/Deployment/$($step.ScriptName)" -OutFile $localPath -UseBasicParsing -ErrorAction Stop
        Write-DeployLog "Downloaded $($step.ScriptName) to $localPath"
        $scriptAvailable = $true
    } catch {
        # If download fails, use local copy if available
        $localSourcePath = Join-Path $PSScriptRoot "Deployment" $step.ScriptName
        if (Test-Path $localSourcePath) {
            Copy-Item $localSourcePath $localPath -Force
            Write-DeployLog "Copied local $($step.ScriptName) to $localPath"
            $scriptAvailable = $true
        } else {
            Write-Warning "Cannot download or find $($step.ScriptName): $_"
            $allSuccessful = $false
            continue
        }
    }
    if ($scriptAvailable) {
        $argumentList = "-ExecutionPolicy Bypass -File `"$localPath`""
        $proc = Start-Process pwsh -ArgumentList $argumentList -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -ne 0) {
            $allSuccessful = $false
        }
    }
}

# Download optional fix Spotlight script. Sometimes Spotlight option is not present and needs a little help.
try {
    $fixScriptPath = Join-Path $dlRoot "Fix-Spotlight.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/Scripts/Deployment/Fix-Spotlight.ps1" -OutFile $fixScriptPath -UseBasicParsing -ErrorAction Stop
    Write-DeployLog "Downloaded Fix-Spotlight.ps1 to $fixScriptPath"
} catch {
    Write-DeployLog "Optional: Could not download Fix-Spotlight.ps1: $_"
}

Write-Output ""
Write-Output "======================================== "
Write-Output "  DEPLOYMENT SUMMARY"
Write-Output "======================================== "
Write-Output ""

if ($allSuccessful) {
    Write-Output "All deployment steps completed successfully!"
} else {
    Write-Output "Some deployment steps failed. Please review the output above."
}
Write-Output ""
Read-Host "Press Enter to exit"
