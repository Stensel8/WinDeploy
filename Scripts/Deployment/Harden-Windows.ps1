# ============================================================================
# Harden-Windows.ps1
# Applies security hardenings to Windows 11 systems.
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
        },

        # Disable SMBv1
        @{
            Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
            Name = "SMB1"
            Value = 0
            Type = "DWord"
            Description = "Disable SMBv1"
        },

        # Disable LLMNR
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
            Name = "EnableMulticast"
            Value = 0
            Type = "DWord"
            Description = "Disable LLMNR"
        },

        # Disable NetBIOS name release
        @{
            Path = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters"
            Name = "NoNameReleaseOnDemand"
            Value = 1
            Type = "DWord"
            Description = "Disable NetBIOS name release on demand"
        },

        # Disable Windows Script Host
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings"
            Name = "Enabled"
            Value = 0
            Type = "DWord"
            Description = "Disable Windows Script Host"
        },

        # Harden UAC
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            Name = "ConsentPromptBehaviorAdmin"
            Value = 2
            Type = "DWord"
            Description = "Harden UAC prompt behavior"
        },

        # Telemetry disable is commented out because it interferes with Intune's Device Health Attestation (DHA).
        # DHA requires telemetry data to assess endpoint health, security posture, and compliance.
        # Disabling telemetry can break DHA reporting, preventing proper monitoring in Intune.
        # @{
        #     Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        #     Name = "AllowTelemetry"
        #     Value = 0
        #     Type = "DWord"
        #     Description = "Disable Windows telemetry"
        # },

        # Disable Bluetooth service
        @{
            Path = "HKLM:\SYSTEM\CurrentControlSet\Services\bthserv"
            Name = "Start"
            Value = 4
            Type = "DWord"
            Description = "Disable Bluetooth service"
        },

        # Enable Memory Integrity
        @{
            Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
            Name = "Enabled"
            Value = 1
            Type = "DWord"
            Description = "Enable Memory Integrity"
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
    Write-DeployLog "AutoRun and security hardenings applied:"
    Write-DeployLog "  - All drive types AutoRun disabled"
    Write-DeployLog "  - autorun.inf execution blocked"
    Write-DeployLog "  - Device metadata from network prevented"
    Write-DeployLog "  - Automatic app installations disabled"
    Write-DeployLog "  - SMBv1 disabled"
    Write-DeployLog "  - LLMNR disabled"
    Write-DeployLog "  - NetBIOS name release disabled"
    Write-DeployLog "  - Windows Script Host disabled"
    Write-DeployLog "  - UAC hardened"
    Write-DeployLog "  - Bluetooth service disabled. Re-enable if needed."
    Write-DeployLog "  - Memory Integrity enabled"

    # Apply power settings for security
    Write-DeployLog ""
    Write-DeployLog "Configuring power settings for security..."
    try {
        # Turn off display after 10 minutes (600 seconds) on AC and DC
        & powercfg /change monitor-timeout-ac 10
        & powercfg /change monitor-timeout-dc 10
        Write-DeployLog "  - Display timeout set to 10 minutes"

        # Put computer to sleep after 30 minutes (1800 seconds) on AC and DC
        & powercfg /change standby-timeout-ac 30
        & powercfg /change standby-timeout-dc 30
        Write-DeployLog "  - Sleep timeout set to 30 minutes"

        # Require password on wake from sleep
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
        & powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
        & powercfg /setactive SCHEME_CURRENT
        Write-DeployLog "  - Password required on wake from sleep"

        # Enable lock after 15 minutes without screensaver
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1"
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "900"  # 15 minutes
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1"
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value ""  # No screensaver, just lock
        Write-DeployLog "  - Lock after 15 minutes of inactivity (no screensaver)"
    } catch {
        Write-DeployLog "  Failed to configure power settings: $($_.Exception.Message)" -IsError
    }
    Write-DeployLog ""

    # Verify AutoRun configuration
    Write-DeployLog "Verifying AutoRun configuration..."

    $verifyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $currentValue = Get-ItemProperty -Path $verifyPath -Name "NoDriveTypeAutoRun" -ErrorAction SilentlyContinue

    if ($currentValue.NoDriveTypeAutoRun -eq 255) {
        Write-DeployLog "Verification successful: AutoRun is disabled for all drive types"
    } else {
        Write-DeployLog "Warning: Verification failed. Current value: $($currentValue.NoDriveTypeAutoRun)" -IsError
    }

    Write-DeployLog ""
    Write-DeployLog "Verifying Memory Integrity configuration..."
    $verifyPathMI = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    $currentValueMI = Get-ItemProperty -Path $verifyPathMI -Name "Enabled" -ErrorAction SilentlyContinue
    if ($currentValueMI.Enabled -eq 1) {
        Write-DeployLog "Verification successful: Memory Integrity is enabled"
    } else {
        Write-DeployLog "Warning: Memory Integrity may not be enabled. Current value: $($currentValueMI.Enabled)" -IsError
    }

    Write-DeployLog ""
    Write-DeployLog "Windows hardening process completed successfully"
    Write-DeployLog "System restart required for Memory Integrity to take effect"

    Write-DeployLog "SUCCESS: Windows hardening done."

} catch {
    Write-DeployLog "Error: $_" -IsError
}