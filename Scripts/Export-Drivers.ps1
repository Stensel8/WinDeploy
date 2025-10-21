# Driver Exporter
# Part of the Deployment Toolkit
# See RELEASES.md for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Exports all third-party drivers from the system to a specified folder.

.DESCRIPTION
    This script exports all non-Microsoft signed drivers from your current Windows installation
    to a target folder, which you specify as a command-line argument. Uses pnputil.exe
    to export driver packages with proper error handling and detailed logging.

.PARAMETER ExportPath
    The folder path where the drivers will be exported. Required.

.EXAMPLE
    .\Export-Drivers.ps1 -ExportPath "C:\drivers\backup"

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
    [string]$ExportPath
)

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
