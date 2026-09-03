[CmdletBinding()]
param(
    # Skips every prompt (BitLocker, WinUtil tweaks, the final "press Enter").
    # Use this for fully unattended runs such as autounattend.xml deployments.
    [switch]$NonInteractive,

    # Passed straight through to the steps that ask for confirmation.
    [ValidateSet('Ask', 'Yes', 'No')]
    [string]$BitLocker = 'Ask',

    # Defaults to Yes: the WinUtil Standard preset's QoL tweaks (disables
    # telemetry, consumer features, Delivery Optimization, etc.) are wanted on
    # every deployment, not opt-in. Pass -Tweaks No to skip it, or -Tweaks Ask
    # to be prompted instead.
    [ValidateSet('Ask', 'Yes', 'No')]
    [string]$Tweaks = 'Yes'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if ($NonInteractive) {
    if ($BitLocker -eq 'Ask') { $BitLocker = 'No' }
    if ($Tweaks -eq 'Ask')    { $Tweaks = 'Yes' }
}

# Waits for Enter, but never longer than $TimeoutSeconds, so an unattended
# deployment cannot sit on a prompt forever.
function Wait-ForExit {
    param([int]$TimeoutSeconds = 120)

    if ($NonInteractive -or -not [Environment]::UserInteractive) { return }
    try { if ([Console]::IsInputRedirected) { return } } catch { return }
    try { $null = $Host.UI.RawUI.KeyAvailable } catch { return }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastShown = -1
    while ((Get-Date) -lt $deadline) {
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($remaining -ne $lastShown) {
            Write-Host ("`rPress Enter to exit (closing automatically in {0}s)   " -f $remaining) -NoNewline
            $lastShown = $remaining
        }
        if ($Host.UI.RawUI.KeyAvailable) {
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Write-Host ""
            return
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ""
}

# Check for minimum PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output "ERROR: This script requires PowerShell 7 or higher."
    exit 1
}

# Fetch latest release with retry logic
function Get-LatestRelease {
    param(
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/THectic-NL/WinDeploy/releases/latest" -ErrorAction Stop
            if ($latestRelease.tag_name) {
                return $latestRelease.tag_name
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "Failed to fetch latest release (attempt $attempt/$MaxRetries): $errorMsg"

            if ($attempt -lt $MaxRetries) {
                if ($errorMsg -match "403|401") {
                    Write-Host "Possible issue: GitHub API rate limit or authentication required" -ForegroundColor Yellow
                } elseif ($errorMsg -match "404") {
                    Write-Host "Possible issue: No releases found in repository" -ForegroundColor Yellow
                }
                Write-Host "Waiting $RetryDelay seconds before retry..." -ForegroundColor Cyan
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }
    return $null
}

# Fetch the latest release tag - REQUIRED for deployment
$releaseTag = Get-LatestRelease
if (!$releaseTag) {
    Write-Output "ERROR: Failed to fetch latest release from GitHub."
    Write-Output "Releases are required for deployment. Development branches are not used."
    Write-Output "Please check:"
    Write-Output "  1. Your internet connection"
    Write-Output "  2. GitHub API accessibility"
    Write-Output "  3. Repository has published releases: github.com/THectic-NL/WinDeploy/releases"
    Wait-ForExit
    exit 1
}

# Read version
$version = $null
try {
    $version = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/THectic-NL/WinDeploy/$releaseTag/VERSION" -ErrorAction SilentlyContinue
    $version = $version.Trim()
    if ($version) {
        Write-Output "Version: $version"
    }
} catch {
    Write-Warning "Failed to fetch version information."
}

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
        Write-Debug "Failed to log to file: $_"
    }

    if ($IsError) {
        # Avoid noisy and spammy error records and stack traces in the console
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

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "ERROR: This script must be run as administrator."
    exit 1
}

# Log execution context for debugging
$scriptExecutionContext = Get-ScriptDisplay
Write-DeployLog "Deployment started. Execution context: $scriptExecutionContext"

# Check if running in Windows Terminal (where left-click doesn't pause)
$isWindowsTerminal = $null -ne $env:WT_SESSION

# Clear screen and show banner and warning
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "            Windows Deployment Automation Toolkit" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
if ($version) {
    Write-Host "Version: $version" -ForegroundColor Green
}
Write-Host ""
Write-Host "Running in PowerShell 7 as Administrator" -ForegroundColor Green
Write-Host ""
if (-not $isWindowsTerminal) {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "          DEPLOYMENT WARNING" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Left click to pause deployment" -ForegroundColor Red
    Write-Host "Right click to resume" -ForegroundColor Green
    Write-Host "CTRL + C to cancel" -ForegroundColor Red
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Countdown before starting
for ($i = 15; $i -gt 0; $i--) {
    Write-Host "`rStarting deployment in $i seconds... (Press CTRL+C to cancel)" -ForegroundColor Yellow -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host "`rStarting deployment now!                                        " -ForegroundColor Green
Write-Host ""

# Helper function to download scripts with retry logic
function Get-DeploymentScript {
    param(
        [string]$ScriptName,
        [string]$LocalPath,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/THectic-NL/WinDeploy/$releaseTag/Scripts/Deployment/$ScriptName" -OutFile $LocalPath -UseBasicParsing -ErrorAction Stop
            Write-DeployLog "Downloaded $ScriptName to $LocalPath"
            return $true
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "Download attempt $attempt/$MaxRetries failed for $ScriptName`: $errorMsg"

            if ($attempt -lt $MaxRetries) {
                # Diagnose the issue
                if ($errorMsg -match "403|401") {
                    Write-Host "Possible issue: GitHub API rate limit reached" -ForegroundColor Yellow
                } elseif ($errorMsg -match "404") {
                    Write-Host "Possible issue: $ScriptName not found in release $releaseTag" -ForegroundColor Yellow
                } elseif ($errorMsg -match "timeout|timed out") {
                    Write-Host "Possible issue: Network timeout" -ForegroundColor Yellow
                }

                Write-Host "Waiting $RetryDelay seconds before retry..." -ForegroundColor Cyan
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    # If all download attempts failed, try local copy
    $localSourcePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "Deployment") -ChildPath $ScriptName
    if (Test-Path $localSourcePath) {
        Copy-Item $localSourcePath $LocalPath -Force
        Write-DeployLog "Copied local $ScriptName to $LocalPath"
        return $true
    }

    Write-Warning "Cannot download or find $ScriptName after $MaxRetries attempts"
    return $false
}

# Define deployment steps (customize as needed)
# Arguments are splatted into the step, so a step can be driven non-interactively.
$deploymentSteps = @(
    @{ Name = "RMM Agent Installation";     ScriptName = "Install-RMMAgent.ps1" }
    @{ Name = "Driver Installation";        ScriptName = "Install-Drivers.ps1" }
    @{ Name = "Windows Hardening";          ScriptName = "Harden-Windows.ps1";  Arguments = @{ BitLocker = $BitLocker } }
    @{ Name = "Application Installation";   ScriptName = "Install-Applications.ps1" }
    @{ Name = "Bloatware Removal";          ScriptName = "Remove-Bloat.ps1" }
    @{ Name = "Optional Tweaks (WinUtil)";  ScriptName = "Apply-Tweaks.ps1";    Arguments = @{ Tweaks = $Tweaks } }
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

    $localPath = Join-Path -Path $dlRoot -ChildPath $step.ScriptName

    # Download script with retry logic
    $scriptAvailable = Get-DeploymentScript -ScriptName $step.ScriptName -LocalPath $localPath

    if ($scriptAvailable) {
        try {
            # Reset first: $LASTEXITCODE is undefined until something sets it
            # (which throws under Set-StrictMode), and otherwise keeps the
            # previous step's value when a step returns without calling exit.
            $global:LASTEXITCODE = 0

            $stepArgs = if ($step.ContainsKey('Arguments')) { $step.Arguments } else { @{} }
            & $localPath @stepArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$($step.Name) completed with errors (Exit Code: $LASTEXITCODE)"
                $allSuccessful = $false
            }
        } catch {
            Write-Warning "$($step.Name) failed: $_"
            $allSuccessful = $false
        }
    } else {
        Write-Warning "Skipping $($step.Name) - script unavailable"
        $allSuccessful = $false
    }
}

# Download optional fix Spotlight script with retry
Write-Output ""
Write-Output "Downloading optional scripts..."
try {
    $fixScriptPath = Join-Path $dlRoot "Fix-Spotlight.ps1"
    $downloaded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/THectic-NL/WinDeploy/$releaseTag/Scripts/Archived/Fix-Spotlight.ps1" -OutFile $fixScriptPath -UseBasicParsing -ErrorAction Stop
            Write-DeployLog "Downloaded Fix-Spotlight.ps1 to $fixScriptPath as an optional script to fix missing Spotlight options on the system. This can be run manually if needed."
            $downloaded = $true
            break
        } catch {
            if ($attempt -lt 3) {
                Start-Sleep -Seconds 5
            }
        }
    }
    if (-not $downloaded) {
        Write-DeployLog "Optional: Could not download Fix-Spotlight.ps1 after 3 attempts"
    }
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
Wait-ForExit
