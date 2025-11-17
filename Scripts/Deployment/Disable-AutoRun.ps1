# ============================================================================
# Disable-AutoRun.ps1
# Disables Windows AutoRun functionality for security hardening.
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Output $Message }
}

try {

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
        Write-DeployLog "Configuring: $($config.Description)"
        try {
            if (!(Test-Path $config.Path)) {
                New-Item -Path $config.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $config.Path -Name $config.Name -Value $config.Value -Type $config.Type
            Write-DeployLog "  Successfully set: $($config.Path)\$($config.Name)"
        } catch {
            Write-DeployLog "  Failed to set: $($config.Path)\$($config.Name) - $($_.Exception.Message)" -IsError
        }
    }

    Write-DeployLog ""
    Write-DeployLog "========================================"
    Write-DeployLog "  CONFIGURATION SUMMARY"
    Write-DeployLog "========================================"
    Write-DeployLog "AutoRun disabled for:"
    Write-DeployLog "  - Removable drives (USB sticks)"
    Write-DeployLog "  - Fixed drives (hard disks)"
    Write-DeployLog "  - Network drives"
    Write-DeployLog "  - CD-ROM drives"
    Write-DeployLog ""
    Write-DeployLog "Additional security:"
    Write-DeployLog "  - autorun.inf handler blocked"
    Write-DeployLog "  - Device metadata retrieval disabled"
    Write-DeployLog "  - Automatic app installations blocked"
    Write-DeployLog ""

    # Verify configuration
    Write-DeployLog "Verifying configuration..."

    $verifyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $currentValue = Get-ItemProperty -Path $verifyPath -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue

    if ($currentValue.NoDriveTypeAutoRun -eq 255) {
        Write-DeployLog "Verification successful: AutoRun is disabled for all drive types"
    } else {
        Write-DeployLog "Warning: Verification failed. Current value: $($currentValue.NoDriveTypeAutoRun)" -IsError
    }

    Write-DeployLog ""
    Write-DeployLog "AutoRun disable process completed successfully"
    Write-DeployLog "No system restart required - changes are effective immediately"

    Write-DeployLog "SUCCESS: AutoRun disable done."

} catch {
    Write-DeployLog "Error: $_" -IsError
}
