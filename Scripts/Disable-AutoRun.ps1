# WinDeploy AutoRun Disabler
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables Windows AutoRun functionality for security hardening.

.DESCRIPTION
    Disables AutoRun and AutoPlay across all drive types to prevent automatic
    execution of potentially malicious code from external media.

.EXAMPLE
    .\Disable-AutoRun.ps1

.NOTES
    Requires : Admin rights
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Disable-AutoRun.log' -RequiredModules @('Logging','System','Registry') -RequireAdmin

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "  AUTORUN DISABLE PROCESS STARTED" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "User: $env:USERNAME" -Level Info
    Write-Log "Computer: $env:COMPUTERNAME" -Level Info
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level Info
    Write-Log "" -Level Info

    # Configuration array for all registry changes
    $registryConfigs = @(
        # Disable AutoRun for all drive types (0xFF = all drives)
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            Name = "NoDriveTypeAutoRun"
            Value = 255  # 0xFF in decimal - disables all drive types
            Type = "DWord"
            Description = "Disable AutoRun for all drive types"
        },

        # Block autorun.inf handler
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\IniFileMapping\Autorun.inf"
            Name = "(Default)"
            Value = "@SYS:DoesNotExist"
            Type = "String"
            Description = "Block autorun.inf execution"
        },

        # Disable device metadata retrieval from Windows Update
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata"
            Name = "PreventDeviceMetadataFromNetwork"
            Value = 1
            Type = "DWord"
            Description = "Prevent device metadata from network"
        },

        # Disable automatic app download with new devices
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer"
            Name = "DisableCoInstallers"
            Value = 1
            Type = "DWord"
            Description = "Disable co-installers for devices"
        }
    )

    # Apply all registry configurations
    foreach ($config in $registryConfigs) {
        Write-Log "Configuring: $($config.Description)" -Level Info

        try {
            Set-RegistryValue -Path $config.Path -Name $config.Name -Value $config.Value -Type $config.Type
            Write-Log "  Successfully set: $($config.Path)\$($config.Name)" -Level Success
        } catch {
            Write-Log "  Failed to set: $($config.Path)\$($config.Name) - $($_.Exception.Message)" -Level Warning
        }
    }

    Write-Log "" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "  CONFIGURATION SUMMARY" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "AutoRun disabled for:" -Level Info
    Write-Log "  - Removable drives (USB sticks)" -Level Info
    Write-Log "  - Fixed drives (hard disks)" -Level Info
    Write-Log "  - Network drives" -Level Info
    Write-Log "  - CD-ROM drives" -Level Info
    Write-Log "  - RAM disks" -Level Info
    Write-Log "" -Level Info
    Write-Log "Additional security:" -Level Info
    Write-Log "  - autorun.inf handler blocked" -Level Info
    Write-Log "  - Device metadata retrieval disabled" -Level Info
    Write-Log "  - Automatic app installations blocked" -Level Info
    Write-Log "" -Level Info

    # Verify configuration
    Write-Log "Verifying configuration..." -Level Info

    $verifyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $currentValue = Get-ItemProperty -Path $verifyPath -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue

    if ($currentValue.NoDriveTypeAutoRun -eq 255) {
        Write-Log "Verification successful: AutoRun is disabled for all drive types" -Level Success
    } else {
        Write-Log "Warning: Verification failed. Current value: $($currentValue.NoDriveTypeAutoRun)" -Level Warning
    }

    Write-Log "" -Level Info
    Write-Log "AutoRun disable process completed successfully" -Level Success
    Write-Log "No system restart required - changes are effective immediately" -Level Info

    exit 0

} catch {
    Write-Log "Critical error during AutoRun disable process: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    Complete-Script
}
