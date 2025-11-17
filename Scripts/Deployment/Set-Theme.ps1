# ============================================================================
# Set-DarkMode.ps1
# Sets dark mode via registry (system, default user, current user).
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
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

    # System-wide (HKLM)
    Write-DeployLog "Setting HKLM keys..."
    $RegOutLM = reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
    $RegOutLM2 = reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "HKLM keys set successfully."
    } else {
        $LMFail = "HKLM failed: $RegOutLM $RegOutLM2"
        Write-DeployLog $LMFail -IsError
        Write-Error $LMFail
    }

    # Default user hive (for new users) - with better access check
    $DefaultHive = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultHive -PathType Leaf) {
        Write-DeployLog "Loading default hive..."
        $LoadOut = reg load "HKU\TempDefault" "$DefaultHive" 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Set keys in loaded hive
            $RegOutDef1 = reg add "HKU\TempDefault\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
            $RegOutDef2 = reg add "HKU\TempDefault\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
            $UnloadOut = reg unload "HKU\TempDefault" 2>&1
            if ($LASTEXITCODE -eq 0 -and $UnloadOut -notmatch "error") {
                Write-DeployLog "Default hive updated successfully. Outputs: $RegOutDef1 $RegOutDef2"
            } else {
                $DefFail = "Default hive unload failed: $UnloadOut. Reg outputs: $RegOutDef1 $RegOutDef2"
                Write-DeployLog $DefFail -IsError
                Write-Error $DefFail
            }
        } else {
            $LoadFail = "Hive load failed: $LoadOut - skipping default user."
            Write-DeployLog $LoadFail -IsError
            Write-Error $LoadFail
        }
    } else {
        Write-DeployLog "Default hive not found or not a file - skipping."
    }

    # Current user (HKCU fallback)
    Write-DeployLog "Setting HKCU keys..."
    $RegOutCU1 = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
    $RegOutCU2 = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "HKCU keys set successfully."
        Write-Output "Dark mode configured - logoff/reboot for full effect."
    } else {
        $CUFail = "HKCU failed: $RegOutCU1 $RegOutCU2"
        Write-DeployLog $CUFail -IsError
        Write-Error $CUFail
    }

    Write-DeployLog "SUCCESS: Dark mode process done."
    exit 0
} catch {
    $CatchErr = $_.Exception.Message
    Write-DeployLog "Unexpected error during setup: $CatchErr" -IsError
    Write-Output "Dark mode partial setup."
    exit 0
}
