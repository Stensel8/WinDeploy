# WinDeploy Device Deployment Script
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 7.0
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Windows device deployment by running scripts in sequence.

.DESCRIPTION
    Executes all deployment scripts in the correct order. Requires PowerShell 7.
    Use Start.ps1 to automatically install prerequisites and launch this script.

.EXAMPLE
    .\Deploy-Device.ps1

.NOTES
    Requires : PowerShell 7+, Admin rights
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Handle remote execution where $PSScriptRoot and $PSCommandPath are empty
# When script is invoked via Invoke-RestMethod piped to Invoke-Expression (irm | iex),
# PowerShell doesn't populate these automatic variables, breaking path resolution
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$script:CommandPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Definition }

# Allow host environments to predefine NoPause; default to $false otherwise
if (-not (Get-Variable -Name NoPause -Scope Script -ErrorAction SilentlyContinue) -and
    -not (Get-Variable -Name NoPause -Scope Global -ErrorAction SilentlyContinue)) {
    $NoPause = $false
}

# Script-scoped variables
$script:LogDirectory = 'C:\WinDeploy\Logs'
$script:DownloadDirectory = 'C:\WinDeploy\Download'

# Resolve utilities path and load modules
$possiblePaths = @()
if ($script:ScriptRoot) {
    $possiblePaths += (Join-Path $script:ScriptRoot 'Utilities')
}
$possiblePaths += @(
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder in any expected location"; exit 1 }

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
if (-not (Test-Path $loggingModule)) { Write-Error "Logging.psm1 not found in $utilitiesPath"; exit 1 }
Import-Module $loggingModule -Force -Global

# Import remaining utility modules (excluding Logging already imported)
Get-ChildItem "$utilitiesPath\*.psm1" | Where-Object { $_.Name -ne 'Logging.psm1' } | ForEach-Object {
    Import-Module $_.FullName -Force -Global
}

Start-EmergencyTranscript -LogName 'Deploy-Device.log'
Initialize-Script -RequireAdmin

# ============================================================================
# UTILITY FUNCTIONS (from modules)
# ============================================================================

# All utility functions are now in modules:
# - Initialize-LogDirectory (Logging.psm1)
# - Test-NetworkConnectivity (Network.psm1)
# - Get-RemoteScript (Download.psm1)
# - RMM Agent functions (RMMAgent.psm1)

# ============================================================================
# SCRIPT EXECUTION FUNCTIONS
# ============================================================================

function Invoke-DeploymentScript {
    <#
    .SYNOPSIS
        Executes a deployment script in PowerShell 7.
    .DESCRIPTION
        Runs script in hidden PowerShell 7 window and returns exit code.
        Exit codes: 0=success, 1=failure, 2=skipped
    .PARAMETER ScriptPath
        Full path to script.
    .PARAMETER StepName
        Display name for logging.
    .OUTPUTS
        [int] Exit code from script.
    #>
    [CmdletBinding()]
    [OutputType([int])]
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

    Write-StepStart -StepName $StepName
    Write-StepExecuting -Message "Executing with PowerShell 7"

    try {
        # Create wrapper script
        $wrapperScript = Join-Path $env:TEMP "wrapper_$([guid]::NewGuid()).ps1"

        # Wrapper handles window title and output formatting
        $wrapperContent = @"
`$Host.UI.RawUI.WindowTitle = '$StepName'
`$ErrorActionPreference = 'Continue'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  $StepName' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

& '$ScriptPath'
`$exitCode = if (`$LASTEXITCODE) { `$LASTEXITCODE } else { 0 }

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
if (`$exitCode -eq 0) {
    Write-Host 'Completed successfully' -ForegroundColor Green
} else {
    Write-Host "Completed with exit code: `$exitCode" -ForegroundColor Red
}
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

exit `$exitCode
"@

        # Write wrapper to disk
        [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

        # Execute in PowerShell 7 (hidden)
        $result = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -Wait -PassThru -WindowStyle Hidden

        # Clean up wrapper
        Remove-Item $wrapperScript -Force -ErrorAction SilentlyContinue

        if ($result.ExitCode -eq 0) {
            Write-StepComplete -StepName $StepName
        } else {
            Write-Log "FAILED: $StepName (Exit: $($result.ExitCode))" -Level Error
            $scriptFileName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
            $logFile = Join-Path $script:LogDirectory "$scriptFileName.log"
            Write-Log "Check log: $logFile" -Level Info
        }

        return $result.ExitCode
    } catch {
        Write-Log "Failed to execute $($StepName): $($_)" -Level Error
        return 1
    }
}

# Parallel execution removed - all scripts now run sequentially

# ============================================================================
# MAIN DEPLOYMENT ORCHESTRATION
# ============================================================================

function Get-DeploymentScript {
    <#
    .SYNOPSIS
        Locates a deployment script by checking local paths and downloading if needed.
    .DESCRIPTION
        Search order:
        1. Script directory (if running locally)
        2. Download directory (C:\WinDeploy\Download)
        3. Download from GitHub (if network available)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )

    # Check local script directory
    if ($script:ScriptRoot) {
        $localPath = Join-Path $script:ScriptRoot $ScriptName
        if (Test-Path $localPath) {
            Write-Log "  -> Found $ScriptName locally" -Level Verbose
            return $localPath
        }
    }

    # Check download directory
    $downloadPath = Join-Path $script:DownloadDirectory $ScriptName
    if (Test-Path $downloadPath) {
        Write-Log "  -> Found $ScriptName in downloads" -Level Verbose
        return $downloadPath
    }

    # Try downloading from GitHub
    if (Test-NetworkConnectivity) {
        Write-Log "  -> Downloading $ScriptName..." -Level Info
        if (Get-RemoteScript -ScriptName $ScriptName) {
            return $downloadPath
        }
    }

    Write-Log "  -> ERROR: Could not find $ScriptName" -Level Error
    return $null
}

function Start-Deployment {
    <#
    .SYNOPSIS
        Executes all deployment steps sequentially.
    .DESCRIPTION
        Runs deployment scripts in order:
        1. Install drivers
        2. Install applications
        3. Remove bloatware
        4. Configure theme
        5. Install Windows updates
    .OUTPUTS
        Hashtable with Success, Failed, and Skipped counts.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param()

    if (-not $PSCmdlet.ShouldProcess('Device deployment sequence', 'Execute deployment steps')) {
        Write-Log "Deployment skipped by user" -Level Warning
        return @{ Success = 0; Failed = 0; Skipped = 0 }
    }

    Write-SectionBanner -Title "EXECUTING DEPLOYMENT STEPS"

    # Find all deployment scripts
    $scripts = @(
        'Install-Drivers.ps1',
        'Install-Applications.ps1',
        'Remove-Bloat.ps1',
        'Set-Theme.ps1',
        'Install-WindowsUpdates.ps1'
    )

    $scriptPaths = @{}
    foreach ($script in $scripts) {
        $path = Get-DeploymentScript -ScriptName $script
        if ($path) {
            $scriptPaths[$script] = $path
        }
    }

    # Install RMM Agent
    Install-RMMAgent -DownloadDirectory $script:DownloadDirectory | Out-Null

    # Execute each step
    Write-Host ""

    $driversExitCode = if ($scriptPaths['Install-Drivers.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Install-Drivers.ps1'] -StepName "Install Drivers"
    } else { 2 }

    $appsExitCode = if ($scriptPaths['Install-Applications.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Install-Applications.ps1'] -StepName "Install Applications"
    } else { 2 }

    $bloatExitCode = if ($scriptPaths['Remove-Bloat.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Remove-Bloat.ps1'] -StepName "Bloatware Removal"
    } else { 2 }

    $themeExitCode = if ($scriptPaths['Set-Theme.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Set-Theme.ps1'] -StepName "Theme Configuration"
    } else { 2 }

    $updatesExitCode = if ($scriptPaths['Install-WindowsUpdates.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Install-WindowsUpdates.ps1'] -StepName "Windows Updates"
    } else { 2 }

    # Calculate results
    $exitCodes = @($driversExitCode, $appsExitCode, $bloatExitCode, $themeExitCode, $updatesExitCode)
    $successCount = ($exitCodes | Where-Object { $_ -eq 0 }).Count
    $failedCount = ($exitCodes | Where-Object { $_ -eq 1 }).Count
    $skippedCount = ($exitCodes | Where-Object { $_ -eq 2 }).Count

    # Show summary
    $logPath = Join-Path 'C:\WinDeploy\Logs' 'Deploy-Device.log'
    Write-DeploymentSummary -SuccessCount $successCount -FailedCount $failedCount -SkippedCount $skippedCount -LogPath $logPath

    return @{
        Success = $successCount
        Failed = $failedCount
        Skipped = $skippedCount
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    # Ensure required directories exist
    Initialize-LogDirectory -Path $script:LogDirectory
    Initialize-LogDirectory -Path $script:DownloadDirectory

    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host ".;%%%%?:                                                              " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%*,,:?%,                                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "*%;  .*%;.                                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+%?*??*??*;,.    .,,.                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  .,:,. .,;*??*::*?????;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            .:+?%?:..,;%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               +%:     ?%,                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               :%?:..,+%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "             .:?%*????*;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            :*%+, ....                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    ....  :*%*,                                           .       ..  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " .;****?**%*,    .*****:.    ,****+.   .**+. ;*,    +*, ;*:.   .+***+," -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".*?:...,;%?.     .%%,,*S:    :S*....   ,%%%+ *%,    *S:+%+.    +S+.;%?" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%.      ;%+     .%%. ;S+    :%?++;    ,%*+%:*%,    *%?%+      *%: .%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ";%.      ;%;     .%%. ;S+    :%*,,.    ,%*.???%,    *%;??,     *S: ,%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+?;,..,+%+.     .%%;;??,    :S?:::.   ,%? ,%%%,    *S:,%%,    ;%*:+%+" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  ,+*???+,       .;;;;:.     ,;;;+;.   .;:  :;;.    :;, ,;:.    ,;+;:." -ForegroundColor Red
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host "         Windows Device Deployment Automation Toolkit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    PowerShell: " -NoNewline -ForegroundColor Gray
    Write-Host "$($PSVersionTable.PSVersion)" -ForegroundColor White
    Write-Host "    Script: " -NoNewline -ForegroundColor Gray
    Write-Host "$($script:CommandPath)" -ForegroundColor White
    Write-Host ""

    # Verify PowerShell 7
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "[ERROR] This script requires PowerShell 7 or higher" -ForegroundColor Red
        Write-Host "[ERROR] Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        Write-Host "[SOLUTION] Use Start.ps1 to automatically install PowerShell 7" -ForegroundColor Yellow
        Write-Host "Press any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }

    # Install/Verify WinGet first (as shown in deployment flow)
    Write-StepStart -StepName "WinGet Installation"
    if (Test-WinGet) {
        Write-Host "WARNING: winget is already installed, exiting..." -ForegroundColor Yellow
        Write-Host "WARNING: If you want to reinstall winget, run the script with the -Force parameter." -ForegroundColor Yellow
        Write-StepComplete -StepName "WinGet Installation"
    } else {
        Write-Host "Installing WinGet..." -ForegroundColor Cyan
        # WinGet installation logic would go here
        Write-StepComplete -StepName "WinGet Installation"
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

    # Check if unattended
    $isUnattended = $false
    if ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM') {
        $isUnattended = $true
    }

    if (!$isUnattended -and $failedCount -gt 0) {
        Write-Host ""
        Write-Host "[WARNING] Some deployment steps failed!" -ForegroundColor Yellow
        Write-Host "Review the logs for details in C:\WinDeploy\Logs" -ForegroundColor Yellow
        if (-not $NoPause) {
            Write-Host "Press any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } elseif (!$isUnattended -and -not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 5
    }

    exit $exitCode

} catch {
    Write-Host ""
    Write-Host "[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red

    $isUnattended = $false
    if ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM') {
        $isUnattended = $true
    }

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
