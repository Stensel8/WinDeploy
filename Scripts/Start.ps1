# WinDeploy Start Script
# Runs all automation scripts in sequence

param(
    [string]$VersionTag
)

# Handle remote execution where $PSScriptRoot and $PSCommandPath are empty
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$script:CommandPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Definition -and (Test-Path $MyInvocation.MyCommand.Definition -ErrorAction SilentlyContinue)) { $MyInvocation.MyCommand.Definition } else { $null }

function Get-VersionReferenceUrl {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    if ([string]::Equals($Tag, 'main', [System.StringComparison]::OrdinalIgnoreCase)) { return 'https://github.com/Stensel8/WinDeploy/tree/main' }
    return "https://github.com/Stensel8/WinDeploy/releases/tag/$Tag"
}

function Get-VersionFromFile {
    param([string[]]$CandidatePaths)
    foreach ($path in ($CandidatePaths | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $path) {
            try {
                $value = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
                if ($value) {
                    $resolvedPath = try { (Resolve-Path $path).Path } catch { $path }
                    return [pscustomobject]@{ Tag = $value; Source = "File: $resolvedPath"; ReleaseUrl = Get-VersionReferenceUrl -Tag $value }
                }
            } catch { continue }
        }
    }
    return $null
}

function Get-LatestReleaseInfo {
    try {
        $headers = @{ 'User-Agent' = 'WinDeploy-Automation' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Stensel8/WinDeploy/releases/latest' -Headers $headers -ErrorAction Stop
        if ($release.tag_name) {
            return [pscustomobject]@{ Tag = $release.tag_name; Source = 'GitHub Release'; ReleaseUrl = $release.html_url }
        }
    } catch {
        Write-Warning "Unable to query GitHub API: $($_.Exception.Message)"
    }
    return $null
}

function Resolve-Version {
    param([string]$RequestedVersion)
    $candidatePaths = @()
    if ($script:CommandPath -and (Test-Path $script:CommandPath -ErrorAction SilentlyContinue)) {
        $candidatePaths += (Join-Path (Split-Path $script:CommandPath -Parent) '..\VERSION')
    }
    if ($script:ScriptRoot) { $candidatePaths += (Join-Path $script:ScriptRoot '..\VERSION') }
    $candidatePaths += (Join-Path (Get-Location).Path 'VERSION')
    $candidatePaths += 'C:\WinDeploy\VERSION'
    $candidatePaths += 'C:\WinDeploy\Download\VERSION'
    $fileInfo = Get-VersionFromFile -CandidatePaths $candidatePaths
    if ($fileInfo) { return $fileInfo }
    if ($RequestedVersion) {
        $trimmed = $RequestedVersion.Trim()
        if ($trimmed) {
            return [pscustomobject]@{ Tag = $trimmed; Source = 'Parameter'; ReleaseUrl = Get-VersionReferenceUrl -Tag $trimmed }
        }
    }
    $releaseInfo = Get-LatestReleaseInfo
    if ($releaseInfo) { return $releaseInfo }
    return [pscustomobject]@{ Tag = 'main'; Source = 'Fallback'; ReleaseUrl = Get-VersionReferenceUrl -Tag 'main' }
}

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Output $Message }
}

$resolvedVersion = Resolve-Version -RequestedVersion $VersionTag
$script:Version = $resolvedVersion.Tag
$script:VersionSource = $resolvedVersion.Source
$script:VersionReleaseUrl = $resolvedVersion.ReleaseUrl

Write-DeployLog "Resolved version: $script:Version (source: $script:VersionSource)"

# Check if admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-DeployLog "Not running as admin. Relaunching with elevation..."
    $argList = @()
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($param.Value -is [switch] -and $param.Value) {
            $argList += "-$($param.Key)"
        } elseif ($param.Value -is [array]) {
            $argList += "-$($param.Key) $($param.Value -join ',')"
        } elseif ($param.Value) {
            $argList += "-$($param.Key) '$($param.Value)'"
        }
    }
    if (-not $PSBoundParameters.ContainsKey('VersionTag') -and $script:Version) { $argList += "-VersionTag '$($script:Version)'" }
    $script = "& { & '$($MyInvocation.MyCommand.Path)' $argList }"
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    exit
}

# ============================================================================
# POWERSHELL 7 CHECK
# ============================================================================
# Deployment requires PowerShell 7 - install and relaunch if needed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "PowerShell 7 required. Checking..."

    # Check if PowerShell 7 is installed
    $pwshPath = $null
    $possiblePaths = @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { $pwshPath = $path; break }
    }

    # Install if not found
    if (-not $pwshPath) {
        Write-DeployLog "PowerShell 7 not found. Installing..."

        # Try WinGet first (fastest method)
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetAvailable) {
        Write-DeployLog "Installing via WinGet..."
            try {
                & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                # Refresh PATH
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                Start-Sleep -Seconds 3
            } catch {
                Write-Warning "WinGet installation failed: $_"
            }
        } else {
            # WinGet not available, use installation scripts
            Write-Warning "WinGet not available. Using installation scripts..."

            # Create download directory
            if (!(Test-Path 'C:\WinDeploy\Download')) {
                New-Item -Path 'C:\WinDeploy\Download' -ItemType Directory -Force | Out-Null
            }

            # Find or download installation scripts
            $wingetScript = Join-Path 'C:\WinDeploy\Download' "Install-Winget.ps1"
            $ps7Script = Join-Path 'C:\WinDeploy\Download' "Install-PowerShell7.ps1"

            # Check local directory first
            if ($script:ScriptRoot) {
                $localWinget = Join-Path $script:ScriptRoot "Install-Winget.ps1"
                $localPs7 = Join-Path $script:ScriptRoot "Install-PowerShell7.ps1"
                if (Test-Path $localWinget) { $wingetScript = $localWinget }
                if (Test-Path $localPs7) { $ps7Script = $localPs7 }
            }

            # Download if not found locally
            if (-not (Test-Path $wingetScript)) {
                try {
                    $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$($script:Version)/Scripts/Install-Winget.ps1"
                    Invoke-WebRequest -Uri $url -OutFile $wingetScript -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Warning "Download failed: $_"
                }
            }

            if (-not (Test-Path $ps7Script)) {
                try {
                    $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$($script:Version)/Scripts/Install-PowerShell7.ps1"
                    Invoke-WebRequest -Uri $url -OutFile $ps7Script -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Warning "Download failed: $_"
                }
            }

            # Install WinGet first
            if (Test-Path $wingetScript) {
                Write-DeployLog "Installing WinGet..."
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wingetScript
                    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                    Start-Sleep -Seconds 2
                } catch {
                    Write-Warning "WinGet install failed: $_"
                }
            }

            # Install PowerShell 7
            if (Test-Path $ps7Script) {
                Write-DeployLog "Installing PowerShell 7..."
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps7Script
                    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                    Start-Sleep -Seconds 3
                } catch {
                    Write-Warning "PowerShell 7 install failed: $_"
                }
            }
        }

        # Check again
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) { $pwshPath = $path; break }
        }
    }

    # Exit if still not found
    if (-not $pwshPath) {
        Write-DeployLog "Failed to install PowerShell 7" -IsError
        Write-Warning "Install manually: https://github.com/PowerShell/PowerShell/releases"
        pause
        exit 1
    }

    # Rebuild argument list
    $argList = @()
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($param.Value -is [switch] -and $param.Value) {
            $argList += "-$($param.Key)"
        } elseif ($param.Value -is [array]) {
            $argList += "-$($param.Key) $($param.Value -join ',')"
        } elseif ($param.Value) {
            $argList += "-$($param.Key) '$($param.Value)'"
        }
    }

    if (-not $PSBoundParameters.ContainsKey('VersionTag') -and $script:Version) {
        $argList += "-VersionTag '$($script:Version)'"
    }

    # Build the script execution command for PowerShell 7
    $script = "& { & '$($MyInvocation.MyCommand.Path)' $argList }"

    # Detect Windows Terminal (to reuse same window)
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $pwshPath }

    # Launch in PowerShell 7
    try {
        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$pwshPath -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        } else {
            Start-Process $pwshPath -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        }

        # Exit current PowerShell 5 session
        exit
    } catch {
        Write-DeployLog "Failed to relaunch in PowerShell 7: $_" -IsError
        pause
        exit 1
    }
}

# ============================================================================
# DEPLOYMENT
# ============================================================================

# Set PowerShell window title to indicate admin mode and PS7
$Host.UI.RawUI.WindowTitle = "WinDeploy - Windows Deployment (Admin - PS7)"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Simple header
Write-Output ""
Write-Output "    ============================================================"
Write-Output ("                       WinDeploy {0}                           " -f $script:Version)
Write-Output "            Windows Deployment Automation Toolkit               "
Write-Output "    ============================================================"
Write-Output ""
Write-Output "    PowerShell: $($PSVersionTable.PSVersion)"
$scriptDisplay = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "https://raw.githubusercontent.com/Stensel8/WinDeploy/main/Scripts/Start.ps1" }
Write-Output "    Script: $scriptDisplay"
Write-Output ""

# Ensure WinGet is installed
Write-Output "Checking WinGet..."
$wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetAvailable) {
    Write-Output "WinGet not found. Installing..."
    try {
        # Download the winget-install script from asheroto (trusted source)
        $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1' -OutFile $tempScript -UseBasicParsing -ErrorAction Stop
        & $tempScript
        Remove-Item $tempScript -Force
        Write-Output "WinGet installed successfully."
    } catch {
        Write-Warning "Failed to install WinGet: $_"
    }
} else {
    Write-Output "WinGet is available."
}
Write-Output ""

# Download function
function Get-DeploymentScript {
    param([string]$ScriptName)
    $localPath = Join-Path $PSScriptRoot "Deployment\$ScriptName"
    if (Test-Path $localPath) { return $localPath }
    $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$script:Version/Scripts/Deployment/$ScriptName"
    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing -ErrorAction Stop
        Write-DeployLog "Downloaded $ScriptName"
    } catch {
        Write-DeployLog "Failed to download $ScriptName" -IsError
    }
    return $localPath
}

# Define deployment steps
$deploymentSteps = @(
    @{ Name = "Driver Installation"; ScriptName = "Install-Drivers.ps1" }
    @{ Name = "RMM Agent Installation"; ScriptName = "Install-RMMAgent.ps1" }
    @{ Name = "AutoRun Disable"; ScriptName = "Disable-AutoRun.ps1" }
    @{ Name = "Application Installation"; ScriptName = "Install-Applications.ps1" }
    @{ Name = "Bloatware Removal"; ScriptName = "Remove-Bloat.ps1" }
    @{ Name = "Theme Configuration"; ScriptName = "Set-Theme.ps1" }
    @{ Name = "Hostname Configuration"; ScriptName = "Set-HostName.ps1" }
    @{ Name = "Windows Updates"; ScriptName = "Install-WindowsUpdates.ps1" }
)

$allSuccessful = $true

foreach ($step in $deploymentSteps) {
    Write-Output ""
    Write-Output "======================================== "
    Write-Output "  $($step.Name)"
    Write-Output "======================================== "
    Write-Output ""

    $scriptPath = Get-DeploymentScript -ScriptName $step.ScriptName
    if (Test-Path $scriptPath) {
        & $scriptPath
        if ($LASTEXITCODE -ne 0) {
            $allSuccessful = $false
        }
    } else {
        Write-Warning "Script $($step.ScriptName) not found"
        $allSuccessful = $false
    }
}

Write-Output ""
Write-Output "======================================== "
Write-Output "  DEPLOYMENT SUMMARY"
Write-Output "======================================== "
Write-Output ""

if ($allSuccessful) {
    Write-DeployLog "All deployment steps completed successfully!"
} else {
    Write-DeployLog "Some deployment steps failed. Please review the output above." -IsError
}

Write-Output ""
Read-Host "Press Enter to exit"
