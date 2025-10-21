# Driver Importer
# Part of the Deployment Toolkit
# See RELEASES.md for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs drivers from a specified folder.

.DESCRIPTION
    This script installs all drivers found recursively in the specified folder.
    Uses pnputil.exe to add and install driver packages with proper error handling
    and detailed logging.

.PARAMETER ImportPath
    The folder path containing driver INF files to install. Required.

.EXAMPLE
    .\Import-Drivers.ps1 -ImportPath ".\drivers\intel"

.NOTES
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Requires     : Admin rights, Windows 10/11
    Version      : See VERSION file in repository root

.LINK
    Project Site: https://github.com/Stensel8/WinDeploy
#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

param(
    [Parameter(Mandatory)]
    [string]$ImportPath
)

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Import-Drivers.log' -RequiredModules @('Logging','System','Driver') -RequireAdmin

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {
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
