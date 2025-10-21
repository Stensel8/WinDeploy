#requires -Version 5.1

<#
.SYNOPSIS
    Main deployment entry point with auto-elevation and PowerShell 7 upgrade.

.DESCRIPTION
    This script handles all prerequisites before running the main deployment:
    - Checks for admin rights and elevates if needed
    - Checks for PowerShell 7 and installs/relaunches if needed
    - Sets up logging and utilities
    - Runs the full deployment sequence

    All logs saved to C:\WinDeploy\Logs\Start.log

.EXAMPLE
    .\Start.ps1

.NOTES
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Version      : See VERSION file in repository root
    Requires     : Windows 11, PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$VersionTag
)

# Handle remote execution where $PSScriptRoot and $PSCommandPath are empty
# When script is invoked via Invoke-RestMethod piped to Invoke-Expression (irm | iex),
# PowerShell doesn't populate these automatic variables, breaking path resolution and script relaunching
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
# Only use MyCommand.Definition if it's a valid file path (not script content)
# When using Invoke-Expression, MyCommand.Definition contains the script content itself instead of a path
$script:CommandPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($MyInvocation.MyCommand.Definition -and (Test-Path $MyInvocation.MyCommand.Definition -ErrorAction SilentlyContinue)) {
    $MyInvocation.MyCommand.Definition
} else {
    $null
}

function Get-VersionReferenceUrl {
    <#
    .SYNOPSIS
        Returns GitHub URL for a version tag.
    #>
    param([string]$Tag)

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $null
    }

    # Main branch gets tree URL, releases get tag URL
    if ([string]::Equals($Tag, 'main', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'https://github.com/Stensel8/WinDeploy/tree/main'
    }

    return "https://github.com/Stensel8/WinDeploy/releases/tag/$Tag"
}

function Get-VersionFromFile {
    <#
    .SYNOPSIS
        Reads version from VERSION file if it exists.
    #>
    param([string[]]$CandidatePaths)

    # Try each path until we find a readable VERSION file
    foreach ($path in ($CandidatePaths | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $path) {
            try {
                $value = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
                if ($value) {
                    return [pscustomobject]@{
                        Tag        = $value
                        Source     = "File: $path"
                        ReleaseUrl = Get-VersionReferenceUrl -Tag $value
                    }
                }
            } catch {
                # Skip unreadable files
                continue
            }
        }
    }

    return $null
}

function Get-LatestReleaseInfo {
    <#
    .SYNOPSIS
        Queries GitHub API for latest release tag.
    #>
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
        Write-Host "Unable to query GitHub API: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $null
}

function Resolve-Version {
    <#
    .SYNOPSIS
        Determines which version to deploy.
    .DESCRIPTION
        Checks multiple sources in priority order:
        1. VERSION file in various locations
        2. Parameter (-VersionTag)
        3. Environment variable ($env:VERSION)
        4. Latest GitHub release
        5. Fallback to 'main' branch
    #>
    param([string]$RequestedVersion)

    # Priority 1: VERSION file
    $candidatePaths = @()
    if ($script:CommandPath -and (Test-Path $script:CommandPath -ErrorAction SilentlyContinue)) {
        try {
            $candidatePaths += (Join-Path (Split-Path $script:CommandPath -Parent) '..\VERSION')
        } catch {
            # Ignore if path operations fail
        }
    }
    if ($script:ScriptRoot) {
        $candidatePaths += (Join-Path $script:ScriptRoot '..\VERSION')
    }
    try {
        $candidatePaths += (Join-Path (Get-Location).Path 'VERSION')
    } catch {
        # Ignore errors reading current location
    }
    $candidatePaths += 'C:\WinDeploy\VERSION'
    $candidatePaths += 'C:\WinDeploy\Download\VERSION'

    $fileInfo = Get-VersionFromFile -CandidatePaths $candidatePaths
    if ($fileInfo) {
        return $fileInfo
    }

    # Priority 2: Explicit parameter
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

    # Priority 3: Environment variable
    if ($env:VERSION) {
        $envVersion = $env:VERSION.Trim()
        if ($envVersion) {
            return [pscustomobject]@{
                Tag        = $envVersion
                Source     = 'Environment'
                ReleaseUrl = Get-VersionReferenceUrl -Tag $envVersion
            }
        }
    }

    # Priority 4: GitHub latest release
    $releaseInfo = Get-LatestReleaseInfo
    if ($releaseInfo) {
        return $releaseInfo
    }

    # Priority 5: Fallback to main branch
    return [pscustomobject]@{
        Tag        = 'main'
        Source     = 'Fallback'
        ReleaseUrl = Get-VersionReferenceUrl -Tag 'main'
    }
}

function Get-RelaunchCommand {
    param([string[]]$ArgumentList)

    $argumentList = $ArgumentList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $argumentString = $argumentList -join ' '

    if ($script:CommandPath) {
        if ($argumentString) {
            return "& { & `'$($script:CommandPath)`' $argumentString }"
        }

        return "& { & `'$($script:CommandPath)`' }"
    }

    $remoteUrl = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$($script:Version)/Scripts/Start.ps1"

    if ($argumentString) {
        return "&([ScriptBlock]::Create((irm '$remoteUrl'))) $argumentString"
    }

    return "&([ScriptBlock]::Create((irm '$remoteUrl')))"
}

$script:VersionSource = 'Embedded'
$script:VersionReleaseUrl = $null

$resolvedVersion = Resolve-Version -RequestedVersion $VersionTag
$script:Version = $resolvedVersion.Tag
$script:VersionSource = $resolvedVersion.Source
$script:VersionReleaseUrl = $resolvedVersion.ReleaseUrl

# ============================================================================
# AUTO-ELEVATION (Step 1: Ensure Admin)
# ============================================================================
# Check if running as admin, if not, relaunch with elevation
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Not running as admin. Relaunching with elevation..." -ForegroundColor Yellow

    # Rebuild arguments from bound parameters
    $argList = @()
    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    # Add version if not already specified
    if (-not $PSBoundParameters.ContainsKey('VersionTag') -and $script:Version) {
        $argList += "-VersionTag '$($script:Version)'"
    }

    # Build relaunch command
    $script = Get-RelaunchCommand -ArgumentList $argList

    # Prefer pwsh (PowerShell 7) if available
    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

    # Use Windows Terminal if available (better UX)
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $powershellCmd }

    # Launch elevated
    try {
        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        } else {
            Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "Failed to elevate: $_" -ForegroundColor Red
        Write-Host "Run this script as Administrator manually" -ForegroundColor Yellow
        pause
        exit 1
    }
}

# ============================================================================
# POWERSHELL 7 CHECK (Step 2: Ensure PowerShell 7)
# ============================================================================
# Deployment requires PowerShell 7 - install and relaunch if needed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "PowerShell 7 required. Checking..." -ForegroundColor Yellow

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
        Write-Host "PowerShell 7 not found. Installing..." -ForegroundColor Cyan

        # Try WinGet first (fastest method)
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetAvailable) {
            Write-Host "Installing via WinGet..." -ForegroundColor Cyan
            try {
                $result = & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements 2>&1

                # Refresh PATH
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                Start-Sleep -Seconds 3
            } catch {
                Write-Host "WinGet installation failed: $_" -ForegroundColor Yellow
            }
        } else {
            # WinGet not available, use installation scripts
            Write-Host "WinGet not available. Using installation scripts..." -ForegroundColor Yellow

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
                    Write-Host "Download failed: $_" -ForegroundColor Yellow
                }
            }

            if (-not (Test-Path $ps7Script)) {
                try {
                    $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$($script:Version)/Scripts/Install-PowerShell7.ps1"
                    Invoke-WebRequest -Uri $url -OutFile $ps7Script -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Host "Download failed: $_" -ForegroundColor Yellow
                }
            }

            # Install WinGet first
            if (Test-Path $wingetScript) {
                Write-Host "Installing WinGet..." -ForegroundColor Cyan
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wingetScript
                    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                    Start-Sleep -Seconds 2
                } catch {
                    Write-Host "WinGet install failed: $_" -ForegroundColor Yellow
                }
            }

            # Install PowerShell 7
            if (Test-Path $ps7Script) {
                Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps7Script
                    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                    Start-Sleep -Seconds 3
                } catch {
                    Write-Host "PowerShell 7 install failed: $_" -ForegroundColor Yellow
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
        Write-Host "Failed to install PowerShell 7" -ForegroundColor Red
        Write-Host "Install manually: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
        pause
        exit 1
    }

    # Rebuild argument list
    $argList = @()
    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    if (-not $PSBoundParameters.ContainsKey('VersionTag') -and $script:Version) {
        $argList += "-VersionTag '$($script:Version)'"
    }

    # Build the script execution command for PowerShell 7
    $script = Get-RelaunchCommand -ArgumentList $argList

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
        Write-Host "Failed to relaunch in PowerShell 7: $_" -ForegroundColor Red
        pause
        exit 1
    }
}

# ============================================================================
# PREREQUISITES MET - Continue with deployment
# ============================================================================

# Set PowerShell window title to indicate admin mode and PS7
$Host.UI.RawUI.WindowTitle = "WinDeploy - Windows Deployment (Admin - PS7)"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ============================================================================
# EARLY ERROR LOGGING (before utilities are loaded)
# ============================================================================
# Create basic logging infrastructure in case utilities fail to load
$script:LogDirectory = 'C:\WinDeploy\Logs'
$script:DownloadDirectory = 'C:\WinDeploy\Download'

if (!(Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
}
if (!(Test-Path $script:DownloadDirectory)) {
    New-Item -Path $script:DownloadDirectory -ItemType Directory -Force | Out-Null
}

$earlyLogFile = Join-Path $script:LogDirectory 'Start-Bootstrap.log'

function Write-BootstrapLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $earlyLogFile -Value $logMessage -Force
    # Console output intentionally suppressed to keep bootstrap quiet
}

Write-BootstrapLog "Starting bootstrap process..." -Level 'INFO'
Write-BootstrapLog "ScriptRoot: $($script:ScriptRoot)" -Level 'INFO'
Write-BootstrapLog "CommandPath: $($script:CommandPath)" -Level 'INFO'
Write-BootstrapLog "Deployment version: $script:Version (source: $script:VersionSource)" -Level 'INFO'
if ($script:VersionReleaseUrl) {
    Write-BootstrapLog "Version reference: $script:VersionReleaseUrl" -Level 'INFO'
}

# ============================================================================
# DOWNLOAD UTILITIES IF MISSING (for remote execution via irm | iex)
# ============================================================================
function Get-GitHubFile {
    param(
        [string]$FilePath,
        [string]$Version = 'main',
        [string]$DestinationPath
    )

    $baseUrl = "https://raw.githubusercontent.com/Stensel8/WinDeploy"
    $url = "$baseUrl/$Version/$FilePath"

    Write-BootstrapLog "Downloading: $url" -Level 'INFO'

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell-WinDeploy-Automation")
        $webClient.DownloadFile($url, $DestinationPath)
        Write-BootstrapLog "  -> Downloaded to: $DestinationPath" -Level 'SUCCESS'
        return $true
    } catch {
        Write-BootstrapLog "  -> Download failed: $_" -Level 'ERROR'
        return $false
    }
}

function Get-GitHubFolder {
    param(
        [string]$FolderPath,
        [string]$Version = 'main',
        [string]$DestinationPath
    )

    # GitHub API to list folder contents
    $apiUrl = "https://api.github.com/repos/Stensel8/WinDeploy/contents/$($FolderPath)?ref=$($Version)"

    Write-BootstrapLog "Fetching folder contents from GitHub API: $FolderPath" -Level 'INFO'
    Write-BootstrapLog "API URL: $apiUrl" -Level 'INFO'

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell-WinDeploy-Automation")
        $json = $webClient.DownloadString($apiUrl)
        $files = $json | ConvertFrom-Json

        if (!(Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }

        $downloadCount = 0
        foreach ($file in $files) {
            if ($file.type -eq 'file') {
                $fileName = $file.name
                $filePath = Join-Path $DestinationPath $fileName

                if (Get-GitHubFile -FilePath "$FolderPath/$fileName" -Version $Version -DestinationPath $filePath) {
                    $downloadCount++
                }
            }
        }

        Write-BootstrapLog "Downloaded $downloadCount files to: $DestinationPath" -Level 'SUCCESS'
        return $true
    } catch {
        Write-BootstrapLog "Failed to download folder: $_" -Level 'ERROR'
        return $false
    }
}

# ============================================================================
# LOAD UTILITIES AND INITIALIZE LOGGING
# ============================================================================
$possiblePaths = @(
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)

# Add script directory to possible paths if available
if ($script:ScriptRoot) {
    $possiblePaths = @((Join-Path $script:ScriptRoot 'Utilities')) + $possiblePaths
}

Write-BootstrapLog "Searching for Utilities folder in:" -Level 'INFO'
foreach ($p in $possiblePaths) {
    Write-BootstrapLog "  - $p" -Level 'INFO'
}

$utilitiesPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $utilitiesPath = $path
        Write-BootstrapLog "Found Utilities at: $path" -Level 'SUCCESS'
        break
    }
}

if (-not $utilitiesPath) {
    Write-BootstrapLog "Utilities folder not found - attempting to download from GitHub..." -Level 'WARNING'
    Write-BootstrapLog "Version: $script:Version" -Level 'INFO'

    $downloadUtilitiesPath = Join-Path $script:DownloadDirectory 'Utilities'

    if (Get-GitHubFolder -FolderPath 'Scripts/Utilities' -Version $script:Version -DestinationPath $downloadUtilitiesPath) {
        if (Test-Path $downloadUtilitiesPath) {
            $utilitiesPath = $downloadUtilitiesPath
            Write-BootstrapLog "Successfully downloaded Utilities folder" -Level 'SUCCESS'
        }
    }
}

if (-not $utilitiesPath) {
    Write-BootstrapLog "CRITICAL: Utilities folder not found and download failed" -Level 'ERROR'
    Write-BootstrapLog "Expected locations checked:" -Level 'ERROR'
    foreach ($p in $possiblePaths) {
        Write-BootstrapLog "  - $p (NOT FOUND)" -Level 'ERROR'
    }
    Write-BootstrapLog "" -Level 'ERROR'
    Write-BootstrapLog "Bootstrap log saved to: $earlyLogFile" -Level 'INFO'
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Red
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
if (-not (Test-Path $loggingModule)) {
    Write-BootstrapLog "CRITICAL: Logging.psm1 not found in $utilitiesPath" -Level 'ERROR'
    Write-BootstrapLog "Bootstrap log saved to: $earlyLogFile" -Level 'INFO'
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Red
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-BootstrapLog "Importing Logging.psm1..." -Level 'INFO'
try {
    Import-Module $loggingModule -Force -Global
    Write-BootstrapLog "Logging module loaded successfully" -Level 'SUCCESS'
} catch {
    Write-BootstrapLog "CRITICAL: Failed to import Logging.psm1 - $_" -Level 'ERROR'
    Write-BootstrapLog "Bootstrap log saved to: $earlyLogFile" -Level 'INFO'
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Red
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Import remaining utility modules after logging is available
Write-BootstrapLog "Loading remaining utility modules..." -Level 'INFO'
Get-ChildItem "$utilitiesPath\*.psm1" | Where-Object { $_.Name -ne 'Logging.psm1' } | ForEach-Object {
    try {
        Import-Module $_.FullName -Force -Global
        Write-BootstrapLog "  -> Loaded $($_.Name)" -Level 'SUCCESS'
    } catch {
        Write-BootstrapLog "  -> WARNING: Failed to load $($_.Name) - $_" -Level 'WARNING'
    }
}

Write-BootstrapLog "Bootstrap complete - switching to main logging system" -Level 'SUCCESS'
Write-BootstrapLog "Main log: Start.log" -Level 'INFO'

Start-EmergencyTranscript -LogName 'Start.log'
Initialize-Script -RequireAdmin

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================
# All utility functions are now in modules:
# - Test-WinGet (WinGet.psm1)
# - Get-RemoteScript (Download.psm1)
# - RMM Agent functions (RMMAgent.psm1)

# Allow host environments to predefine NoPause; default to $false otherwise
if (-not (Get-Variable -Name NoPause -Scope Script -ErrorAction SilentlyContinue) -and
    -not (Get-Variable -Name NoPause -Scope Global -ErrorAction SilentlyContinue)) {
    $NoPause = $false
}

Write-Log "Deployment version resolved to $script:Version" -Level Info
if ($script:VersionSource) {
    Write-Log "Version source: $script:VersionSource" -Level Verbose
}
if ($script:VersionReleaseUrl) {
    Write-Log "Version reference: $script:VersionReleaseUrl" -Level Verbose
}

function Invoke-DeploymentScript {
    [OutputType([int])]
    <#
    .SYNOPSIS
        Runs a deployment script in a separate PowerShell 7 process with its own log file.
    .PARAMETER ScriptPath
        Full path to the script to execute.
    .PARAMETER StepName
        Display name for this deployment step.
    .OUTPUTS
        Exit code from the script (0 = success, 1 = failure).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [string]$StepName
    )

    if (!(Test-Path $ScriptPath)) {
        Write-Log "Script not found: $ScriptPath" -Level Error
        return 1
    }

    Write-Host ""
    Write-Host "► $StepName" -ForegroundColor Cyan
    Write-UserMessage ("- {0}: Running..." -f $StepName) -Color Cyan

    try {
        # Create wrapper script that runs in separate process with its own transcript
        $wrapperScript = Join-Path $env:TEMP "wrapper_$([guid]::NewGuid()).ps1"
        # Create log filename from script name (e.g., Install-Drivers.ps1 -> Install-Drivers.log)
        $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
        $logFileName = "$scriptBaseName.log"
        $logFile = Join-Path $script:LogDirectory $logFileName

        # Build wrapper - starts its own transcript then runs the child script
        $wrapperContent = @"
`$Host.UI.RawUI.WindowTitle = '$StepName'
`$ErrorActionPreference = 'Continue'
`$env:DEPLOYMENT_CHILD_PROCESS = '1'

# Start transcript for this script
`$logPath = '$logFile'
Start-Transcript -Path `$logPath -Append -Force | Out-Null

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  $StepName' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# Run the actual deployment script
& '$ScriptPath'
`$exitCode = if (`$LASTEXITCODE) { `$LASTEXITCODE } else { 0 }

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
if (`$exitCode -eq 0) {
    Write-Host 'Script completed successfully. Exit code: 0' -ForegroundColor Green
} elseif (`$exitCode -eq 2) {
    Write-Host 'Script skipped - unsupported device. Exit code: 2' -ForegroundColor Yellow
} else {
    Write-Host "Script completed with errors. Exit code: `$exitCode" -ForegroundColor Red
}
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

Stop-Transcript | Out-Null
exit `$exitCode
"@

        # Save wrapper script
        [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

        # Execute in separate pwsh process (non-blocking)
        $tempOutput = Join-Path $env:TEMP "output_$([guid]::NewGuid()).txt"
        $tempError = Join-Path $env:TEMP "error_$([guid]::NewGuid()).txt"

        $process = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -PassThru -WindowStyle Hidden -RedirectStandardOutput $tempOutput -RedirectStandardError $tempError

        # Monitor log file in real-time while process runs
        # Start from end of existing log file to avoid re-displaying old content from previous runs
        $lastPosition = if (Test-Path $logFile) {
            (Get-Item $logFile).Length
        } else {
            0
        }
        $logCheckInterval = 500  # Check every 500ms

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds $logCheckInterval

            if (Test-Path $logFile) {
                try {
                    # Read new content from log file
                    $fileStream = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
                    $fileStream.Position = $lastPosition
                    $reader = New-Object System.IO.StreamReader($fileStream)
                    $newContent = $reader.ReadToEnd()
                    $lastPosition = $fileStream.Position
                    $reader.Close()
                    $fileStream.Close()

                    if ($newContent) {
                        # Parse each new line
                        $newLines = $newContent -split "`r?`n" | Where-Object { $_ }

                        foreach ($line in $newLines) {
                            # Skip bloatware "Searching" verbose lines (keep in log, hide from console)
                            if ($line -match 'Searching (installed|provisioned) packages matching:') {
                                continue
                            }

                            # Skip lines that are just "Caching" messages
                            if ($line -match 'Caching all (installed|provisioned) packages') {
                                continue
                            }

                            # Skip separator lines (===, ---) - they clutter the output
                            if ($line -match '^[\s]*={3,}[\s]*$' -or $line -match '^[\s]*-{3,}[\s]*$') {
                                continue
                            }

                            # Extract and display important messages
                            if ($line -match '^\[.*?\] \[(Info|Success|Warning|Error)\] (.+)$') {
                                $level = $matches[1]
                                $message = $matches[2]

                                # Skip verbose messages (they clutter the output)
                                if ($level -eq 'Verbose') {
                                    continue
                                }

                                # Color based on level
                                $color = switch ($level) {
                                    'Success' { 'Green' }
                                    'Warning' { 'Yellow' }
                                    'Error' { 'Red' }
                                    default { 'DarkGray' }
                                }

                                Write-Host "  $message" -ForegroundColor $color
                            }
                            # Show important Write-Host output from transcript (headers, steps, summaries)
                            # But skip separator lines and plain list items
                            elseif ($line -match '^(Step \d+:|  \[|\[|Applications to install/Update:|Updates to install:|Successfully installed:|Failed/skipped:|Device detected:|Matched pattern:)') {
                                Write-Host "  $line" -ForegroundColor DarkGray
                            }
                            # Show application list items (indented with "  - ")
                            elseif ($line -match '^  - .+') {
                                Write-Host "  $line" -ForegroundColor DarkGray
                            }
                        }
                    }
                } catch {
                    # File might be locked, skip this iteration
                }
            }
        }

        # Wait for process to complete and get exit code
        $process.WaitForExit()
        $result = $process

        # Cleanup temp files without displaying
        if (Test-Path $tempOutput) {
            Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempError) {
            Remove-Item $tempError -Force -ErrorAction SilentlyContinue
        }

        # Cleanup
        Remove-Item $wrapperScript -Force -ErrorAction SilentlyContinue

        # Show result
        if ($result.ExitCode -eq 0) {
            Write-UserMessage ("- {0}: Completed" -f $StepName) -Color Green
        } elseif ($result.ExitCode -eq 2) {
            Write-UserMessage ("- {0}: Skipped (unsupported device)" -f $StepName) -Color Yellow
            Write-Log "SKIPPED: $StepName - Unsupported device" -Level Warning
        } else {
            Write-UserMessage ("- {0}: Failed (Exit Code: {1})" -f $StepName, $result.ExitCode) -Color Red
            Write-Log "FAILED: $StepName (Exit Code: $($result.ExitCode))" -Level Error
            Write-Log "Check log: $logFile" -Level Info
        }

        # Add spacing after step completion for better readability
        Write-Host ""

        return $result.ExitCode
    } catch {
        Write-Log "Failed to execute $StepName - $_" -Level Error
        return 1
    }
}


function Get-DeploymentScript {
    <#
    .SYNOPSIS
        Locates a deployment script in order: ScriptRoot -> Download folder -> GitHub
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )

    # Check 1: Same directory as this script (only if ScriptRoot exists)
    if ($script:ScriptRoot) {
        $localPath = Join-Path $script:ScriptRoot $ScriptName
        if (Test-Path $localPath) {
            Write-Log "  -> Found $ScriptName in script directory" -Level Verbose
            return $localPath
        }
    }

    # Check 2: Download directory
    $downloadPath = Join-Path $script:DownloadDirectory $ScriptName
    if (Test-Path $downloadPath) {
        Write-Log "  -> Found $ScriptName in download directory" -Level Verbose
        return $downloadPath
    }

    # Check 3: Try to download from GitHub
    if (Test-NetworkConnectivity) {
        Write-Log "  -> Downloading $ScriptName from GitHub (version: $script:Version)..." -Level Info
        if (Get-RemoteScript -ScriptName $ScriptName -Version $script:Version) {
            # Install-Drivers.ps1 depends on device list JSON files from the Docs folder
            # These files define which Dell/HP models are supported for automatic driver installation
            # Without these files, all devices would be incorrectly marked as "unsupported"
            if ($ScriptName -eq 'Install-Drivers.ps1') {
                # Download the required Docs folder JSON files
                $docsPath = Join-Path $script:DownloadDirectory 'Docs'
                if (-not (Test-Path $docsPath)) {
                    New-Item -Path $docsPath -ItemType Directory -Force | Out-Null
                }

                $baseUrl = if ($script:Version -eq 'main') {
                    "https://raw.githubusercontent.com/Stensel8/WinDeploy/refs/heads/main/Docs"
                } else {
                    "https://raw.githubusercontent.com/Stensel8/WinDeploy/$($script:Version)/Docs"
                }

                $requiredDocs = @('SupportedDellDevices.json', 'SupportedHPDevices.json')
                foreach ($docFile in $requiredDocs) {
                    $docUrl = "$baseUrl/$docFile"
                    $docPath = Join-Path $docsPath $docFile
                    try {
                        $webClient = New-Object System.Net.WebClient
                        $webClient.Headers.Add("User-Agent", "PowerShell-WinDeploy-Automation")
                        $webClient.DownloadFile($docUrl, $docPath)
                        $webClient.Dispose()
                        Write-Log "  -> Downloaded $docFile" -Level Verbose
                    } catch {
                        Write-Log "  -> WARNING: Could not download $docFile - $_" -Level Warning
                    }
                }
            }
            return $downloadPath
        }
    }

    Write-Log "  -> ERROR: Could not find $ScriptName" -Level Error
    return $null
}

function Start-Deployment {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param()

    if (-not $PSCmdlet.ShouldProcess('Deployment sequence', 'Execute all deployment steps')) {
        Write-Log "Deployment sequence was skipped by user confirmation." -Level Warning
        return @{ Success = 0; Failed = 0; Skipped = 0; Details = @() }
    }

    Write-SectionBanner -Title "EXECUTING DEPLOYMENT STEPS"

    # Define all deployment steps in order
    $deploymentSteps = @(
        @{ Name = "Driver Installation"; ScriptName = "Install-Drivers.ps1" }
        @{ Name = "Application Installation"; ScriptName = "Install-Applications.ps1" }
        @{ Name = "Bloatware Removal"; ScriptName = "Remove-Bloat.ps1" }
        @{ Name = "Intune Hash Generation"; ScriptName = "Get-IntuneHash.ps1" }
        @{ Name = "Theme Configuration"; ScriptName = "Set-Theme.ps1" }
        @{ Name = "Windows Updates"; ScriptName = "Install-WindowsUpdates.ps1" }
    )

    # Install RMM Agent first
    Install-RMMAgent -DownloadDirectory $script:DownloadDirectory | Out-Null

    Write-Host ""

    # Execute all steps sequentially
    $results = @{
        Success = 0
        Failed = 0
        Skipped = 0
        Details = @()
    }

    foreach ($step in $deploymentSteps) {
        $scriptPath = Get-DeploymentScript -ScriptName $step.ScriptName

        if ($scriptPath) {
            $exitCode = Invoke-DeploymentScript -ScriptPath $scriptPath -StepName $step.Name

            if ($exitCode -eq 0) {
                $results.Success++
            } elseif ($exitCode -eq 2) {
                $results.Skipped++
            } else {
                $results.Failed++
            }

            $results.Details += @{
                Name = $step.Name
                Script = $step.ScriptName
                ExitCode = $exitCode
                Success = ($exitCode -eq 0)
                Skipped = ($exitCode -eq 2)
            }

            # Add 2-second pause between deployment steps for better readability
            Start-Sleep -Seconds 2
        } else {
            Write-Log "SKIPPED: $($step.Name) - Script not found" -Level Warning
            $results.Skipped++
        }
    }

    # Get log path for summary
    $logPath = Join-Path $script:LogDirectory 'Start.log'

    # Display summary
    Write-DeploymentSummary -SuccessCount $results.Success -FailedCount $results.Failed -SkippedCount $results.Skipped -LogPath $logPath

    return $results
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Initialize-LogDirectory -Path $script:LogDirectory
    Initialize-LogDirectory -Path $script:DownloadDirectory

    # Original Denko ICT ASCII art logo created by Sten Tijhuis
    # Preserved here as a tribute to the project's origins! Feel free to create your own ASCII art.
    # To use it, uncomment the lines below:
    <#
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host "  #########                                                                                         " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "############                                                                                        " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "####    ####                                                                                        " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "####     ###                                                                                        " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "###############                                                                                     " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " ##################        ###                                                                      " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    ####     #########  ##########                                                                  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                 ##################                                                                 " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                     #####      ####                                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                     ####        ###                                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                      ####      ####                                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                      #############                                                                 " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                    ##############                                                                  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                   #####   ####                                                                     " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "                 #####                                                                              " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               #####                                                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    ###############      #########        ########       ####   ####      ####  ####        ######  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  ###############        ##########       ########       #####  ####      #### #####       #########" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " ####       ####         ####  ####       ####           ###### ####      #########       ####  ####" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "###          ####        ####   ###       ########       ###########      ########        ####   ###" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "###          ####        ####   ####      ########       ### #######      #######         ####   ###" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "###          ####        ####   ###       ####           ### #######      ########        ####  ####" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " ####       ####         #### #####       ####           ###  ######      #### ####       ##### ####" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  #############          #########        #########      ###   #####      ####  ####       ######## " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    #########            #######          ########       ###   #####      ####   ###          ##    " -ForegroundColor Red
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host "         Windows Device Deployment Automation Toolkit" -ForegroundColor Gray
    #>

    # Simple header for now - add your own ASCII art here!
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan

    $displayVersion = $script:Version

    Write-Host ("                       WinDeploy {0}                           " -f $displayVersion) -ForegroundColor Green
    Write-Host "            Windows Deployment Automation Toolkit               " -ForegroundColor Gray
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    PowerShell: " -NoNewline -ForegroundColor Gray
    Write-Host "$($PSVersionTable.PSVersion)" -ForegroundColor White
    Write-Host "    Script: " -NoNewline -ForegroundColor Gray
    Write-Host "$($script:CommandPath)" -ForegroundColor White
    Write-Host ""

    # Verify WinGet is installed
    Write-UserMessage "- WinGet Installation: Checking..." -Color Cyan
    Write-Log "[WINGET] Checking WinGet availability..." -Level Info
    $wg = Test-WinGet
    if ($wg.IsAvailable) {
        Write-UserMessage "- WinGet Installation: Already installed (v$($wg.Version))" -Color Green
        Write-Log "[WINGET] WinGet already installed (v$($wg.Version))" -Level Success
    } else {
        Write-UserMessage "- WinGet Installation: Not found (will be handled by scripts if needed)" -Color Yellow
        Write-Log "[WINGET] WinGet not found - checking installation requirements..." -Level Info
        Write-Log "[WINGET] WinGet installation would be handled by individual scripts if needed" -Level Info
    }

    # Run main deployment
    $deploymentResults = Start-Deployment

    # Determine exit code
    $failedCount = 0
    if ($deploymentResults -and $deploymentResults.Failed) {
        $failedCount = $deploymentResults.Failed
    }

    $exitCode = 0
    if ($failedCount -gt 0) {
        $exitCode = 1
    }

    # Check if running in unattended mode (OOBE/Autopilot)
    $isUnattended = Test-UnattendedMode

    if (!$isUnattended) {
        # Interactive mode - always pause before exit
        Write-Log "" -Level Info
        if ($failedCount -gt 0) {
            Write-Log "Some deployment steps failed!" -Level Warning
            Write-Log "Review logs in C:\WinDeploy\Logs for details" -Level Info
        } else {
            Write-Log "ALL DEPLOYMENT STEPS COMPLETED" -Level Success
            Write-Log "Logs: C:\WinDeploy\Logs" -Level Info
        }
        Write-Log "" -Level Info

        # Always pause unless NoPause is explicitly set
        if (-not $NoPause) {
            $color = if ($failedCount -gt 0) { 'Yellow' } else { 'Cyan' }
            Write-Host "Press any key to exit..." -ForegroundColor $color
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } else {
        # Unattended mode - wait 5 seconds then exit
        Start-Sleep -Seconds 5
    }

    exit $exitCode

} catch {
    Write-Log "" -Level Error
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error

    $isUnattended = Test-UnattendedMode

    if (!$isUnattended) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 10
    }

    exit 1
} finally {
    if (Get-Command Complete-Script -ErrorAction SilentlyContinue) {
        try { Complete-Script } catch { Stop-EmergencyTranscript }
    } else {
        Stop-EmergencyTranscript
    }
}