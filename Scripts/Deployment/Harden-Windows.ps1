# ============================================================================
# Harden-Windows.ps1
# Applies security hardenings to Windows 11 systems.
# Standalone script - can be deployed via any management tool.
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Check for Intune enrollment (pre-check)
function Test-IntuneEnrollment {
    $enrollments = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue
    if ($enrollments.Count -eq 0) { return $false }
    foreach ($enrollment in $enrollments) {
        $guid = $enrollment.PSChildName
        $erm = "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\$guid"
        $policy = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$guid"
        $omadm = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$guid"
        $task = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\EnterpriseMgmt\$guid"
        if ((Test-Path $erm) -and (Test-Path $policy) -and (Test-Path $omadm) -and (Test-Path $task)) {
            return $true
        }
    }
    return $false
}

if (Test-IntuneEnrollment) {
    Write-Output "Device is already enrolled in Intune. Skipping hardening."
    exit 0
}

# Only support Windows 11 25H2+ (build 26200+)
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($build -lt 26200) {
    Write-Output "ERROR: Only Windows 11 25H2 (build 26200+) and newer are supported. Current build: $build. Exiting."
    exit 1
}

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $logFile = Join-Path $logDir "$scriptName.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Output $Message }
}

#region Configuration
$registryConfigs = @(
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        Name = "NoDriveTypeAutoRun"
        Value = 255
        Type = "DWord"
        Description = "AutoRun disabled"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\IniFileMapping\Autorun.inf"
        Name = "(Default)"
        Value = "@SYS:DoesNotExist"
        Type = "String"
        Description = "Autorun.inf blocked"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer"
        Name = "DisableCoInstallers"
        Value = 1
        Type = "DWord"
        Description = "Device co-installers disabled"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Name = "SMB1"
        Value = 0
        Type = "DWord"
        Description = "SMBv1 disabled - https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3?tabs=server"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Name = "SMB2"
        Value = 0
        Type = "DWord"
        Description = "SMBv2 disabled - https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3?tabs=server"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings"
        Name = "Enabled"
        Value = 0
        Type = "DWord"
        Description = "Windows Script Host disabled"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
        Name = "EnableBDE"
        Value = 1
        Type = "DWord"
        Description = "BitLocker policy enabled"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
        Name = "EncryptionMethod"
        Value = 7
        Type = "DWord"
        Description = "BitLocker XTS-AES-256 set"
        Silent = $true
    }
)

$monitorTimeoutMinutes = 10
$standbyTimeoutMinutes = 30
$screenSaverTimeoutSeconds = 900
#endregion

Write-DeployLog "Starting Windows hardening process..."
$appliedConfigs = @()
$failedConfigs = @()

# Apply registry configurations
foreach ($config in $registryConfigs) {
    try {
        if (!(Test-Path $config.Path)) {
            New-Item -Path $config.Path -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $config.Path -Name $config.Name -Value $config.Value -Type $config.Type -ErrorAction Stop
        if (-not ($config.ContainsKey('Silent') -and $config['Silent'])) {
            $appliedConfigs += $config.Description
        }
    } catch {
        $errorMsg = "$($config.Description) - $($_.Exception.Message)"
        if ($config.ContainsKey('SkipOnError') -and $config['SkipOnError']) {
            Write-DeployLog "Skipped: $errorMsg"
        } else {
            Write-DeployLog "Failed: $errorMsg" -IsError
            $failedConfigs += $config.Description
        }
    }
}

# Enable BitLocker
try {
    $tpm = Get-Tpm -ErrorAction Stop

    if (-not $tpm.TpmPresent) {
        throw "TPM not present"
    }
    if (-not $tpm.TpmEnabled) {
        throw "TPM not enabled"
    }
    if (-not $tpm.TpmActivated) {
        throw "TPM not activated"
    }

    if (-not $tpm.TpmOwned) {
        Write-DeployLog "Initializing TPM ownership..."
        Initialize-Tpm -AllowClear -AllowPhysicalPresence -ErrorAction Stop
    }

    $bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    if ($bitLockerStatus.ProtectionStatus -eq "Off") {
        Enable-BitLocker -MountPoint "C:" -TpmProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop
        $appliedConfigs += "BitLocker encryption started"
        Write-Output "WARNING: BitLocker will be enabled after the next reboot. Make sure to export your BitLocker recovery key!"
    } else {
        $appliedConfigs += "BitLocker already active"
    }
} catch {
    Write-DeployLog "BitLocker skipped: $($_.Exception.Message)" -IsError
    $failedConfigs += "BitLocker"
}

# Configure power settings
try {
    & powercfg /change monitor-timeout-ac $monitorTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change monitor-timeout-dc $monitorTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change standby-timeout-ac $standbyTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change standby-timeout-dc $standbyTimeoutMinutes 2>&1 | Out-Null
    & powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 2>&1 | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null

    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1" -ErrorAction Stop
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "$screenSaverTimeoutSeconds" -ErrorAction Stop
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -ErrorAction Stop
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value "" -ErrorAction Stop

    $appliedConfigs += "Power/lock settings configured"
} catch {
    Write-DeployLog "Power settings failed: $($_.Exception.Message)" -IsError
    $failedConfigs += "Power settings"
}

# Verification
$verifications = @(
    @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255}
)

$verifyFailed = $false
foreach ($verify in $verifications) {
    try {
        $value = (Get-ItemProperty -Path $verify.Path -Name $verify.Name -ErrorAction Stop).$($verify.Name)
        if ($value -ne $verify.Expected) {
            $verifyFailed = $true
        }
    } catch {
        $verifyFailed = $true
    }
}

# Links for more information
$hardeningLinks = @{
    "AutoRun disabled" = "https://en.wikipedia.org/wiki/AutoRun"
    "Autorun.inf blocked" = "https://en.wikipedia.org/wiki/AutoRun"
    "Device co-installers disabled" = "https://learn.microsoft.com/en-us/previous-versions/windows/drivers/install/co-installer-functionality"
    "SMBv1 disabled" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3?tabs=server"
    "Windows Script Host disabled" = "https://en.wikipedia.org/wiki/Windows_Script_Host"
    "BitLocker policy enabled" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/"
    "BitLocker already active" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/"
    "Power/lock settings configured" = "https://learn.microsoft.com/en-us/windows/win32/power/power-management-portal"
}

# Summary output
Write-Output ""
Write-Output "Applied security hardenings:"
foreach ($config in $appliedConfigs) {
    $link = if ($hardeningLinks.ContainsKey($config)) { " - $($hardeningLinks[$config])" } else { "" }
    Write-Output "  • $config$link"
}

if ($failedConfigs.Count -gt 0) {
    Write-Output ""
    Write-Output "Failed tasks:"
    foreach ($failed in $failedConfigs) {
        Write-Output "  • $failed"
    }
}

Write-Output ""
Write-Output "Note: For extra security, manually enable Tamper Protection and Memory Integrity in Windows Security Center."

Write-Output ""
if ($failedConfigs.Count -eq 0 -and -not $verifyFailed) {
    Write-DeployLog "SUCCESS: All hardening tasks completed. Restart required for full effect."
} elseif ($failedConfigs.Count -gt 0) {
    Write-DeployLog "PARTIAL SUCCESS: Some tasks failed. Restart required." -IsError
} else {
    Write-DeployLog "SUCCESS: Tasks completed. Restart required."
}
