# WinDeploy First Logon Animation Disabler
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables Windows first logon animation.

.DESCRIPTION
    Sets registry key to disable the animated first-sign-in experience for all users.

.EXAMPLE
    .\DisableFirstLogonAnimation.ps1

.NOTES
    Requires : Admin rights
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
Import-Module (Join-Path $utilitiesPath 'Registry.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'DisableFirstLogonAnimation.log'
Initialize-Script -RequireAdmin

try {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    Set-RegistryValue -Path $regPath -Name 'EnableFirstLogonAnimation' -Value 0 -Type 'DWord'
    Write-Log 'First logon animation disabled' -Level Success

    Set-IntuneSuccess -AppName 'DisableFirstLogonAnimation' -Version '2.0.0'
    exit 0
} catch {
    Write-Log "Failed to disable first logon animation: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Complete-Script
}
