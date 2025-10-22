# WinDeploy Driver Import Utility
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs drivers from a specified folder.

.DESCRIPTION
    Installs all drivers found recursively in the specified folder using
    pnputil.exe with proper error handling and logging.

.PARAMETER ImportPath
    The folder path containing driver INF files. Required.

.EXAMPLE
    .\Import-Drivers.ps1 -ImportPath ".\drivers\intel"

.NOTES
    Requires : Admin rights, Windows 11
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ImportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Import-Drivers.log' -RequiredModules @('Logging','System','Driver') -RequireAdmin

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {
    # Warning and confirmation prompt
    Write-Host "`nWARNING: Installing third-party drivers can affect system stability." -ForegroundColor Yellow
    Write-Host "You are doing this at your own risk. Ensure drivers are from trusted sources.`n" -ForegroundColor Yellow
    
    $confirmation = Read-Host "Do you want to continue? (Y/N)"
    if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
        Write-Log "Driver import cancelled by user." -Level Warning
        Write-Host "Operation cancelled." -ForegroundColor Cyan
        exit 0
    }

    $result = Install-DriversFromPath -Path $ImportPath

    # Exit with error if any failures
    exit $(if ($result.Failed -gt 0) { 1 } else { 0 })

} catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    if ($_.ScriptStackTrace) {
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    }
    exit 1
} finally {
    Complete-DeploymentScript
}
