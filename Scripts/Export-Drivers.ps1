# WinDeploy Driver Export Utility
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Exports third-party drivers to a specified folder.

.DESCRIPTION
    Exports all non-Microsoft signed drivers from the current Windows installation
    using pnputil.exe with proper error handling and logging.

.PARAMETER ExportPath
    The folder path where drivers will be exported. Required.

.EXAMPLE
    .\Export-Drivers.ps1 -ExportPath "C:\drivers\backup"

.NOTES
    Requires : Admin rights, Windows 11
#>

param(
    [Parameter(Mandatory, Position=0)]
    [string]$ExportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Export-Drivers.log' -RequiredModules @('Logging','System','Driver') -RequireAdmin

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {
    $result = Export-DriverPackage -Path $ExportPath

    # Exit with error if export failed
    exit $(if ($result.Success) { 0 } else { 1 })

} catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    if ($_.ScriptStackTrace) {
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    }
    exit 1
} finally {
    Complete-DeploymentScript
}
