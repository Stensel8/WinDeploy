<#PSScriptInfo

.AUTHOR Sten Tijhuis

.COMPANYNAME WinDeploy

.TAGS PowerShell Windows Deployment Intune FirstLogonAnimation Policy

.PROJECTURI https://github.com/Stensel8/WinDeploy

#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables the Windows first logon animation for all users.

.DESCRIPTION
    Sets registry key to disable the animated first-sign-in experience.

.EXAMPLE
    .\DisableFirstLogonAnimation.ps1

.NOTES
    Version      : See VERSION file in repository root
    Author       : Sten Tijhuis
    Project      : WinDeploy
    Requirements : Administrative privileges, Windows PowerShell 5.1+
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
