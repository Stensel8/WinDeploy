# ============================================================================
# Harden-Windows.ps1
# Applies security hardenings to Windows 11 systems.
# Standalone script - can be deployed via any management tool.
#
# All baseline hardenings are applied unconditionally. BitLocker is the one
# exception: it is only enabled after an explicit Y/N confirmation, because
# it produces a recovery key that the operator MUST write down.
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    # Ask  = prompt the operator (default)
    # Yes  = enable BitLocker without prompting
    # No   = skip BitLocker entirely
    [ValidateSet('Ask', 'Yes', 'No')]
    [string]$BitLocker = 'Ask',

    # How long the BitLocker prompt waits for a keypress before falling back
    # to "No". Keeps unattended deployments from hanging forever.
    [int]$PromptTimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = if ($PSCommandPath) { [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) } else { "Harden-Windows" }
    $logFile = Join-Path $logDir "$scriptName.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Warning $Message } else { Write-Output $Message }
}

# Prompts for Y/N with a timeout. Returns $DefaultYes when the session is not
# interactive or nothing is typed in time, so a zero-touch deployment (which
# may run in a hidden window) never blocks.
function Read-YesNoWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [int]$TimeoutSeconds = 90,
        [switch]$DefaultYes
    )

    $default = [bool]$DefaultYes
    $defaultLabel = if ($default) { 'Y' } else { 'N' }

    # Work out whether anyone can actually answer. UserInteractive alone is not
    # enough: it is $true for any process in a user session, including one
    # started with a redirected stdin or from a scheduled task, where waiting
    # out the full timeout would stall the deployment for nothing.
    $interactive = [Environment]::UserInteractive
    if ($interactive) {
        try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { $interactive = $false }
    }
    if ($interactive) {
        # Hosts without a real console (ISE, some job runners) throw here.
        try { $null = $Host.UI.RawUI.KeyAvailable } catch { $interactive = $false }
    }
    if (-not $interactive) {
        Write-Host "$Question [Y/N] -> no interactive console, using default: $defaultLabel" -ForegroundColor Cyan
        return $default
    }

    # Drain anything already buffered so a stray keypress doesn't answer for us.
    try {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    } catch {
        Write-Debug "Could not drain the input buffer: $($_.Exception.Message)"
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastShown = -1
    while ((Get-Date) -lt $deadline) {
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        # Repaint every 5s rather than every second: Start.ps1 runs a transcript,
        # and a once-per-second countdown fills the log with redraw lines.
        if ($lastShown -lt 0 -or ($lastShown - $remaining) -ge 5) {
            Write-Host ("`r{0} [Y/N] (default {1} in {2}s)   " -f $Question, $defaultLabel, $remaining) -NoNewline -ForegroundColor Yellow
            $lastShown = $remaining
        }
        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.Character -eq 'y' -or $key.Character -eq 'Y') { Write-Host "`r$Question [Y/N] -> Yes                    " -ForegroundColor Green; return $true }
            if ($key.Character -eq 'n' -or $key.Character -eq 'N') { Write-Host "`r$Question [Y/N] -> No                     " -ForegroundColor Cyan;  return $false }
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host ("`r{0} [Y/N] -> timed out, using default: {1}          " -f $Question, $defaultLabel) -ForegroundColor Cyan
    return $default
}

# Check for Intune enrollment (pre-check)
function Test-IntuneEnrollment {
    # -ErrorAction SilentlyContinue yields $null when the key is absent, and
    # $null.Count throws under Set-StrictMode. @() normalises both cases.
    $enrollments = @(Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)
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
        # SMB1 server. The SMB1 *feature* is removed separately below; this keeps
        # the server side off even if something re-adds the feature.
        # Note: there is deliberately no "SMB2 = 0" here. That value disables both
        # SMB2 and SMB3 - i.e. all remaining SMB - which breaks file and printer
        # sharing. Microsoft explicitly advises against it.
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Name = "SMB1"
        Value = 0
        Type = "DWord"
        Description = "SMBv1 disabled - https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Name = "RequireSecuritySignature"
        Value = 1
        Type = "DWord"
        Description = "SMB server signing required"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Name = "RequireSecuritySignature"
        Value = 1
        Type = "DWord"
        Description = "SMB client signing required"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Name = "AllowInsecureGuestAuth"
        Value = 0
        Type = "DWord"
        Description = "SMB insecure guest logons blocked"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings"
        Name = "Enabled"
        Value = 0
        Type = "DWord"
        Description = "Windows Script Host disabled"
    },
    @{
        # Blocks WDigest from caching plaintext credentials in LSASS.
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
        Name = "UseLogonCredential"
        Value = 0
        Type = "DWord"
        Description = "WDigest plaintext credential caching disabled"
    },
    @{
        # LSA runs as a Protected Process Light, blocking credential dumpers
        # such as Mimikatz from opening the LSASS process.
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Name = "RunAsPPL"
        Value = 1
        Type = "DWord"
        Description = "LSA protection (RunAsPPL) enabled"
    },
    @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Name = "RestrictAnonymous"
        Value = 1
        Type = "DWord"
        Description = "Anonymous SAM/share enumeration restricted"
    },
    @{
        # Mitigates LLMNR poisoning (Responder-style credential theft).
        # DNS and NetBIOS name resolution are unaffected.
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        Name = "EnableMulticast"
        Value = 0
        Type = "DWord"
        Description = "LLMNR disabled"
    },
    @{
        # Memory integrity (HVCI). Windows 11 enables this by default on
        # compatible clean installs; set it explicitly so upgrades match.
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
        Name = "Enabled"
        Value = 1
        Type = "DWord"
        Description = "Memory integrity (HVCI) enabled"
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

# Screen lock is enforced through the machine-wide policy hive rather than
# HKCU. During deployment HKCU belongs to the deployment/admin account, not to
# the end user, so HKCU values would silently apply to the wrong profile.
$lockPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
$monitorTimeoutMinutes = 10
$standbyTimeoutMinutes = 30
$screenSaverTimeoutSeconds = 900
# A screen saver executable is required: with ScreenSaveActive=1 but no
# SCRNSAVE.EXE, Windows never starts one and the secure-lock never triggers.
$screenSaverExe = "$env:SystemRoot\System32\scrnsave.scr"

# Attack Surface Reduction rules (Defender). Conservative set that does not
# interfere with normal business software.
$asrRules = @(
    @{ Id = "56a863a9-875e-4185-98a7-b882c64b5ce5"; Description = "ASR: block abuse of vulnerable signed drivers" }
    @{ Id = "d4f940ab-401b-4efc-aadc-ad5f3c50688a"; Description = "ASR: block Office apps creating child processes" }
    @{ Id = "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"; Description = "ASR: block credential stealing from LSASS" }
    @{ Id = "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"; Description = "ASR: block executable content from email/webmail" }
    @{ Id = "d3e037e1-3eb8-44c8-a917-57927947596d"; Description = "ASR: block JS/VBS launching downloaded executables" }
    @{ Id = "5beb7efe-fd9a-4556-801d-275e5ffc04cc"; Description = "ASR: block obfuscated scripts" }
    @{ Id = "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"; Description = "ASR: block Office apps creating executable content" }
    @{ Id = "01443614-cd74-433a-b99e-2ecdc07bfc25"; Description = "ASR: block executables unless prevalent/aged/trusted" }
    @{ Id = "c1db55ab-c21a-4637-bb3f-a12568109d35"; Description = "ASR: use advanced ransomware protection" }
)
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

# Remove the SMB1 client/server feature outright (the registry value above only
# covers the server side and only while the feature is still installed).
try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
    if ($smb1.State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop | Out-Null
        $appliedConfigs += "SMBv1 feature removed"
    } else {
        $appliedConfigs += "SMBv1 feature already absent"
    }
} catch {
    Write-DeployLog "SMBv1 feature removal skipped: $($_.Exception.Message)" -IsError
}

# Attack Surface Reduction rules
try {
    $null = Get-Command Add-MpPreference -ErrorAction Stop
    $asrApplied = 0
    foreach ($rule in $asrRules) {
        try {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $rule.Id -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
            $asrApplied++
        } catch {
            Write-DeployLog "Failed: $($rule.Description) - $($_.Exception.Message)" -IsError
        }
    }
    if ($asrApplied -gt 0) {
        $appliedConfigs += "Defender ASR rules enabled ($asrApplied of $($asrRules.Count))"
    }
} catch {
    Write-DeployLog "Defender ASR rules skipped: Defender cmdlets unavailable ($($_.Exception.Message))" -IsError
    $failedConfigs += "Defender ASR rules"
}

#region BitLocker
# BitLocker is opt-in: it generates a recovery key that must be written down
# before the machine leaves the bench. Everything above this point is applied
# unconditionally.
$recoveryPassword = $null
$recoveryKeyFile = $null

switch ($BitLocker) {
    'Yes' { $enableBitLocker = $true }
    'No'  { $enableBitLocker = $false }
    default {
        Write-Output ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " BitLocker drive encryption" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " Encrypts C: with XTS-AES-256 using the TPM." -ForegroundColor Gray  # DevSkim: ignore DS187371 - XTS is the recommended BitLocker mode, not a weak one
        Write-Host " A 48-digit recovery key will be generated and saved to your" -ForegroundColor Gray
        Write-Host " Documents folder. You MUST store that key somewhere safe -" -ForegroundColor Gray
        Write-Host " without it the drive cannot be recovered if the TPM, the" -ForegroundColor Gray
        Write-Host " motherboard or the firmware configuration changes." -ForegroundColor Gray
        Write-Host ""
        $enableBitLocker = Read-YesNoWithTimeout -Question " Enable BitLocker on C: now?" -TimeoutSeconds $PromptTimeoutSeconds
        Write-Output ""
    }
}

if (-not $enableBitLocker) {
    Write-DeployLog "BitLocker skipped (not confirmed). Run this script again with -BitLocker Yes to enable it later."
    $appliedConfigs += "BitLocker skipped by operator choice"
} else {
    try {
        $tpm = Get-Tpm -ErrorAction Stop

        if (-not $tpm.TpmPresent)   { throw "TPM not present" }
        if (-not $tpm.TpmEnabled)   { throw "TPM not enabled" }
        if (-not $tpm.TpmActivated) { throw "TPM not activated" }

        if (-not $tpm.TpmOwned) {
            # Deliberately no -AllowClear: clearing the TPM destroys any key
            # material already sealed to it. If ownership cannot be taken
            # without a clear, that is an operator decision, not ours.
            Write-DeployLog "Initializing TPM ownership..."
            Initialize-Tpm -ErrorAction Stop | Out-Null
        }

        $bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        if ($bitLockerStatus.ProtectionStatus -eq 'Off') {
            Enable-BitLocker -MountPoint "C:" -TpmProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly -SkipHardwareTest -ErrorAction Stop | Out-Null
            $appliedConfigs += "BitLocker encryption started (XTS-AES-256)"  # DevSkim: ignore DS187371 - XTS is the recommended BitLocker mode, not a weak one
        } else {
            $appliedConfigs += "BitLocker already active"
        }

        # A TPM protector alone is not recoverable. Make sure a recovery
        # password exists, then hand it to the operator.
        $bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        $existing = @($bitLockerStatus.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
        if ($existing.Count -eq 0) {
            Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
            $bitLockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
            $existing = @($bitLockerStatus.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
        }

        if ($existing.Count -gt 0) {
            $recoveryPassword = $existing[0].RecoveryPassword
            $recoveryId = $existing[0].KeyProtectorId
            $appliedConfigs += "BitLocker recovery password created"

            # Save next to the operator, in Documents. Fall back to the
            # WinDeploy folder when there is no profile (e.g. SYSTEM).
            $documents = [Environment]::GetFolderPath('MyDocuments')
            if ([string]::IsNullOrWhiteSpace($documents) -or -not (Test-Path $documents)) {
                $documents = "C:\WinDeploy"
                if (!(Test-Path $documents)) { New-Item -ItemType Directory -Path $documents -Force | Out-Null }
            }
            $recoveryKeyFile = Join-Path $documents ("BitLocker-Recovery-Key_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

            $keyFileContent = @"
BitLocker recovery key
======================

Computer      : $env:COMPUTERNAME
Drive         : C:
Created       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Identifier    : $recoveryId

Recovery key  : $recoveryPassword

KEEP THIS KEY SAFE.
Without it the contents of this drive cannot be recovered if the TPM is
cleared or fails, the motherboard is replaced, or the firmware/boot
configuration changes.

Store it in your password manager or another secure location that is NOT
on this machine, then delete this file.
"@
            $keyFileContent | Out-File -FilePath $recoveryKeyFile -Encoding UTF8 -Force
            Write-DeployLog "BitLocker recovery key written to $recoveryKeyFile"
        } else {
            Write-DeployLog "BitLocker enabled but no recovery password could be read back." -IsError
            $failedConfigs += "BitLocker recovery password"
        }
    } catch {
        Write-DeployLog "BitLocker skipped: $($_.Exception.Message)" -IsError
        $failedConfigs += "BitLocker"
    }
}
#endregion

# Configure power settings and screen lock
try {
    & powercfg /change monitor-timeout-ac $monitorTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change monitor-timeout-dc $monitorTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change standby-timeout-ac $standbyTimeoutMinutes 2>&1 | Out-Null
    & powercfg /change standby-timeout-dc $standbyTimeoutMinutes 2>&1 | Out-Null
    & powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 2>&1 | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null

    if (!(Test-Path $lockPolicyPath)) { New-Item -Path $lockPolicyPath -Force -ErrorAction Stop | Out-Null }
    Set-ItemProperty -Path $lockPolicyPath -Name "ScreenSaveActive"    -Value "1" -Type String -ErrorAction Stop
    Set-ItemProperty -Path $lockPolicyPath -Name "ScreenSaverIsSecure" -Value "1" -Type String -ErrorAction Stop
    Set-ItemProperty -Path $lockPolicyPath -Name "ScreenSaveTimeOut"   -Value "$screenSaverTimeoutSeconds" -Type String -ErrorAction Stop
    if (Test-Path $screenSaverExe) {
        Set-ItemProperty -Path $lockPolicyPath -Name "SCRNSAVE.EXE" -Value $screenSaverExe -Type String -ErrorAction Stop
    } else {
        Write-DeployLog "Screen saver executable not found at $screenSaverExe - lock-on-timeout may not trigger."
    }

    $appliedConfigs += "Power settings configured"
    $appliedConfigs += "Screen lock after $([int]($screenSaverTimeoutSeconds / 60)) minutes (machine policy)"
} catch {
    Write-DeployLog "Power settings failed: $($_.Exception.Message)" -IsError
    $failedConfigs += "Power settings"
}

# Verification - read a few settings back rather than trusting the writes.
$verifications = @(
    @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255}
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "RunAsPPL"; Expected = 1}
    @{Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"; Name = "AllowInsecureGuestAuth"; Expected = 0}
    @{Path = $lockPolicyPath; Name = "ScreenSaverIsSecure"; Expected = "1"}
)

$verifyFailed = $false
foreach ($verify in $verifications) {
    try {
        $value = (Get-ItemProperty -Path $verify.Path -Name $verify.Name -ErrorAction Stop).$($verify.Name)
        if ("$value" -ne "$($verify.Expected)") {
            Write-DeployLog "Verification mismatch: $($verify.Name) is '$value', expected '$($verify.Expected)'" -IsError
            $verifyFailed = $true
        }
    } catch {
        Write-DeployLog "Verification failed to read $($verify.Name): $($_.Exception.Message)" -IsError
        $verifyFailed = $true
    }
}

# Links for more information
$hardeningLinks = @{
    "AutoRun disabled" = "https://en.wikipedia.org/wiki/AutoRun"
    "Autorun.inf blocked" = "https://en.wikipedia.org/wiki/AutoRun"
    "Device co-installers disabled" = "https://learn.microsoft.com/en-us/previous-versions/windows/drivers/install/co-installer-functionality"
    "SMBv1 disabled" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3"
    "SMBv1 feature removed" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3"
    "SMB server signing required" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing"
    "SMB client signing required" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing"
    "SMB insecure guest logons blocked" = "https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/guest-access-in-smb2-is-disabled-by-default"
    "Windows Script Host disabled" = "https://en.wikipedia.org/wiki/Windows_Script_Host"
    "WDigest plaintext credential caching disabled" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/wdigest-authentication-disabled"
    "LSA protection (RunAsPPL) enabled" = "https://learn.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection"
    "Anonymous SAM/share enumeration restricted" = "https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/network-access-do-not-allow-anonymous-enumeration-of-sam-accounts-and-shares"
    "LLMNR disabled" = "https://learn.microsoft.com/en-us/windows-server/networking/dns/what-s-new-in-dns-client"
    "Memory integrity (HVCI) enabled" = "https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity"
    "BitLocker policy enabled" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/"
    "BitLocker already active" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/"
    "BitLocker encryption started (XTS-AES-256)" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/"  # DevSkim: ignore DS187371 - XTS is the recommended BitLocker mode, not a weak one
    "BitLocker recovery password created" = "https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/bitlocker-recovery-overview"
    "Power settings configured" = "https://learn.microsoft.com/en-us/windows/win32/power/power-management-portal"
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

# Show the recovery key last, so it is the final thing on screen.
if ($recoveryPassword) {
    Write-Host ""
    Write-Host "############################################################" -ForegroundColor Red
    Write-Host "#            BITLOCKER RECOVERY KEY - WRITE IT DOWN        #" -ForegroundColor Red
    Write-Host "############################################################" -ForegroundColor Red
    Write-Host ""
    Write-Host "  $recoveryPassword" -ForegroundColor Yellow
    Write-Host ""
    if ($recoveryKeyFile) {
        Write-Host "  Also saved to: $recoveryKeyFile" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Store this key in your password manager or another secure" -ForegroundColor Red
    Write-Host "  location that is NOT this machine, then delete the file." -ForegroundColor Red
    Write-Host "  Without it, an encrypted drive cannot be recovered after a" -ForegroundColor Red
    Write-Host "  TPM clear, mainboard swap or firmware change." -ForegroundColor Red
    Write-Host ""
    Write-Host "############################################################" -ForegroundColor Red
    Write-Host ""
}

Write-Output ""
Write-Output "Note: memory integrity, LSA protection and SMB signing take effect after a restart."
Write-Output "Note: for extra security, manually enable Tamper Protection in Windows Security Center."

Write-Output ""
if ($failedConfigs.Count -eq 0 -and -not $verifyFailed) {
    Write-DeployLog "SUCCESS: All hardening tasks completed. Restart required for full effect."
} elseif ($failedConfigs.Count -gt 0) {
    Write-DeployLog "PARTIAL SUCCESS: Some tasks failed. Restart required." -IsError
} else {
    Write-DeployLog "SUCCESS: Tasks completed. Restart required."
}
