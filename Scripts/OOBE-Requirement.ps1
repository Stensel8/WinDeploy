# WinDeploy OOBE Context Validator
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Verifies device is running in OOBE context.

.DESCRIPTION
    Checks if current user is defaultuser0 or SYSTEM, indicating OOBE/Autopilot context.

.EXAMPLE
    .\OOBE-Requirement.ps1

.NOTES
    Requires : PowerShell 5.1+, Admin rights
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'System.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'OOBE-Requirement.log'
Initialize-Script -RequireAdmin

try {
    if (Test-OOBEContext) {
        Write-Log "OOBE context verified (user: $env:USERNAME)" -Level Success
        exit 0
    } else {
        Write-Log "Not running in OOBE context (user: $env:USERNAME)" -Level Warning
        exit 1
    }
} catch {
    Write-Log "OOBE requirement check failed: $_" -Level Error
    exit 1
} finally {
    Complete-Script
}