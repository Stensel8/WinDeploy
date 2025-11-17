# WinDeploy Start Script
# Runs all automation scripts in sequence

param(
    [string]$VersionTag
)

# Handle remote execution where $PSScriptRoot and $PSCommandPath are empty
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$script:CommandPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($MyInvocation.MyCommand.Definition -and (Test-Path $MyInvocation.MyCommand.Definition -ErrorAction SilentlyContinue)) {
    $MyInvocation.MyCommand.Definition
} else {
    $null
}

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
                    return [pscustomobject]@{
                        Tag        = $value
                        Source     = "File: $resolvedPath"
                        ReleaseUrl = Get-VersionReferenceUrl -Tag $value
                    }
                }
            } catch {
                continue
            }
        }
    }
    return $null
}

function Get-LatestReleaseInfo {
    try {
        $headers = @{ 'User-Agent' = 'WinDeploy-Automation' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Stensel8/WinDeploy/releases/latest' -Headers $headers -ErrorAction Stop
        if ($release.tag_name) {
            return [pscustomobject]@{
                Tag        = $release.tag_name
                Source     = 'GitHub Release'
                ReleaseUrl = $release.html_url
            }
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
    if ($script:ScriptRoot) {
        $candidatePaths += (Join-Path $script:ScriptRoot '..\VERSION')
    }
    $candidatePaths += (Join-Path (Get-Location).Path 'VERSION')
    $candidatePaths += 'C:\WinDeploy\VERSION'
    $candidatePaths += 'C:\WinDeploy\Download\VERSION'

    $fileInfo = Get-VersionFromFile -CandidatePaths $candidatePaths
    if ($fileInfo) { return $fileInfo }

    if ($RequestedVersion) {
        $trimmed = $RequestedVersion.Trim()
        if ($trimmed) {
            return [pscustomobject]@{
                Tag        = $trimmed
                Source     = 'Parameter'
                ReleaseUrl = Get-VersionReferenceUrl -Tag $trimmed
            }
        }
    }

    $releaseInfo = Get-LatestReleaseInfo
    if ($releaseInfo) { return $releaseInfo }

    return [pscustomobject]@{
        Tag        = 'main'
        Source     = 'Fallback'
        ReleaseUrl = Get-VersionReferenceUrl -Tag 'main'
    }
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
        # Ignore logging errors to prevent script failure
    }

    if ($IsError) {
        # Avoid noisy error records and stack traces in the console
        Write-Warning $Message
    } else {
        Write-Output $Message
    }
}

# Resolve version info
$resolvedVersion         = Resolve-Version -RequestedVersion $VersionTag
$script:Version          = $resolvedVersion.Tag
$script:VersionSource    = $resolvedVersion.Source
$script:VersionReleaseUrl = $resolvedVersion.ReleaseUrl

# Write version to download dir for scripts to use
$downloadDir = "C:\WinDeploy\Download"
if (!(Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}
$script:Version | Out-File -FilePath (Join-Path $downloadDir "VERSION") -Force

Write-DeployLog "Resolved version: $script:Version (source: $script:VersionSource)"

# Helper to display script / execution source in the banner
function Get-ScriptDisplay {
    # 1. Normal script execution from disk
    if ($PSCommandPath) {
        return "Script: $PSCommandPath"
    }

    if ($script:CommandPath) {
        return "Script: $script:CommandPath"
    }

    if ($MyInvocation.MyCommand.Path) {
        return "Script: $($MyInvocation.MyCommand.Path)"
    }

    # 2. No physical path => in-memory execution (iex/irm)
    $versionSegment = if ($script:Version) { $script:Version } else { 'main' }
    $onlineUrl      = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$versionSegment/Scripts/Start.ps1"

    if ($MyInvocation.MyCommand.CommandType -eq 'Script') {
        return "Execution: Remote (via Invoke-Expression) - Source: $onlineUrl"
    }

    return "Execution: In-memory (no script path) - Source: $onlineUrl"
}

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

    if (-not $PSBoundParameters.ContainsKey('VersionTag') -and $script:Version) {
        $argList += "-VersionTag '$($script:Version)'"
    }

    $scriptCmd = "& { & '$($MyInvocation.MyCommand.Path)' $argList }"
    Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$scriptCmd`"" -Verb RunAs
    exit
}

# ============================================================================
# POWERSHELL 7 CHECK
# ============================================================================
# Deployment requires PowerShell 7 - install and relaunch if needed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "PowerShell 7 required. Checking..."

    function Get-PwshPath {
        $possiblePaths = @(
            'C:\Program Files\PowerShell\7\pwsh.exe',
            'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                return $path
            }
        }
        return $null
    }

    $pwshPath = Get-PwshPath

    # Install if not found
    if (-not $pwshPath) {
        Write-DeployLog "PowerShell 7 not found. Installing..."

        $installed = $false

        # 1. Try WinGet first (best-effort)
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-DeployLog "Attempting to install PowerShell 7 via WinGet..."
            try {
                & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
            } catch {
                Write-Warning "WinGet install of PowerShell 7 threw: $_"
            }

            # Refresh PATH and re-check
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3

            $pwshPath = Get-PwshPath
            if ($pwshPath) {
                $installed = $true
                Write-DeployLog "PowerShell 7 installed via WinGet."
            } else {
                Write-Warning "WinGet reported completion but PowerShell 7 was not found on disk."
            }
        } else {
            Write-DeployLog "WinGet not available; skipping WinGet method."
        }

        # 2. Fallback: official install-powershell.ps1 (MSI, works in OOBE)
        if (-not $installed) {
            Write-DeployLog "Falling back to install-powershell.ps1 (MSI)..."
            try {
                # Equivalent to: iex "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
                Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -UseMSI -Quiet"
            } catch {
                Write-Warning "install-powershell.ps1 MSI method threw: $_"
            }

            # Refresh PATH and re-check
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3

            $pwshPath = Get-PwshPath
            if ($pwshPath) {
                $installed = $true
                Write-DeployLog "PowerShell 7 installed via install-powershell.ps1 (MSI)."
            } else {
                Write-Warning "install-powershell.ps1 MSI method completed but PowerShell 7 was not found on disk."
            }
        }
    }

    # Exit if still not found
    if (-not $pwshPath) {
        Write-DeployLog "Failed to install PowerShell 7" -IsError
        Write-Warning "Failed to install PowerShell 7 automatically. Install manually: https://github.com/PowerShell/PowerShell/releases"
        Read-Host "Press Enter to exit"
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
    $scriptCmd = "& { & '$($MyInvocation.MyCommand.Path)' $argList }"

    # Detect Windows Terminal (to reuse same window)
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $pwshPath }

    # Launch in PowerShell 7
    try {
        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$pwshPath -ExecutionPolicy Bypass -NoProfile -Command `"$scriptCmd`"" -Verb RunAs
        } else {
            Start-Process $pwshPath -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$scriptCmd`"" -Verb RunAs
        }

        # Exit current Windows PowerShell 5 session
        exit
    } catch {
        Write-DeployLog "Failed to relaunch in PowerShell 7: $_" -IsError
        Read-Host "Press Enter to exit"
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
Write-Output ("    {0}" -f (Get-ScriptDisplay))
Write-Output ""

# Ensure WinGet is installed (for later use in deployment scripts)
Write-Output "Checking WinGet..."
$wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetAvailable) {
    Write-Output "WinGet not found. Installing..."
    try {
        # Download the winget-install script from asheroto (trusted community source)
        $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1' -OutFile $tempScript -UseBasicParsing -ErrorAction Stop
        # Run the script in a separate process to prevent it from exiting this script
        Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Wait -NoNewWindow
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

    $downloadDir = "C:\WinDeploy\Download"
    if (!(Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    }

    $downloadPath = Join-Path $downloadDir $ScriptName

    if (!(Test-Path $downloadPath)) {
        $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/testing/Scripts/Deployment/$ScriptName"
        try {
            Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
            Write-DeployLog "Downloaded $ScriptName to $downloadPath"
        } catch {
            Write-DeployLog "Failed to download $ScriptName from $url" -IsError
            return $null
        }
    }

    return $downloadPath
}

# Define deployment steps
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

$allSuccessful = $true

foreach ($step in $deploymentSteps) {
    Write-Output ""
    Write-Output "======================================== "
    Write-Output "  $($step.Name)"
    Write-Output "======================================== "
    Write-Output ""

    $scriptPath = Get-DeploymentScript -ScriptName $step.ScriptName
    if ($scriptPath -and (Test-Path $scriptPath)) {
        try {
            $argumentList = "-ExecutionPolicy Bypass -File `"$scriptPath`""
            $proc = Start-Process pwsh -ArgumentList $argumentList -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0) {
                $allSuccessful = $false
            }
        } catch {
            Write-Warning "Failed to run $($step.ScriptName): $_"
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
