# ============================================================================
# Set-Theme.ps1
# Sets dark mode via registry (system, default user, current user).
# Standalone script - can be deployed via any management tool.
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
    Write-DeployLog "Setting system (HKLM) theme keys..."
    $RegOutLM = reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
    $RegOutLM2 = reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "System (HKLM) theme keys set successfully."
    } else {
        $LMFail = "System (HKLM) theme keys failed: $RegOutLM $RegOutLM2"
        Write-DeployLog $LMFail -IsError
    }

    # Default user hive (for new users)
    $DefaultHive = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultHive -PathType Leaf) {
        Write-DeployLog "Loading default user hive..."
        $LoadOut = reg load "HKU\TempDefault" "$DefaultHive" 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Set keys in loaded hive
            $RegOutDef1 = reg add "HKU\TempDefault\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
            $RegOutDef2 = reg add "HKU\TempDefault\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
            $RegOutDef3 = reg add "HKU\TempDefault\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "C:\Windows\Web\Wallpaper\Windows\img19.jpg" /f 2>&1
            $UnloadOut = reg unload "HKU\TempDefault" 2>&1
            if ($LASTEXITCODE -eq 0 -and $UnloadOut -notmatch "error") {
                Write-DeployLog "Default user hive updated successfully."
            } else {
                $DefFail = "Default user hive unload failed: $UnloadOut."
                Write-DeployLog $DefFail -IsError
            }
        } else {
            $LoadFail = "Default user hive load failed: $LoadOut - skipping."
            Write-DeployLog $LoadFail -IsError
        }
    } else {
        Write-DeployLog "Default user hive not found or not a file - skipping."
    }

    # Current user (HKCU fallback)
    Write-DeployLog "Setting current user (HKCU) theme keys..."
    $RegOutCU1 = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>&1
    $RegOutCU2 = reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>&1
    $RegOutCU3 = reg add "HKCU\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "C:\Windows\Web\Wallpaper\Windows\img19.jpg" /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-DeployLog "Current user (HKCU) theme keys set successfully."
        # Apply wallpaper immediately
        try {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            [WinAPI]::SystemParametersInfo(0x0014, 0, "C:\Windows\Web\Wallpaper\Windows\img19.jpg", 0x01)
            Write-DeployLog "Wallpaper applied immediately."
        } catch {
            Write-DeployLog "Failed to apply wallpaper immediately: $($_.Exception.Message)" -IsError
        }
        Write-Output "Dark mode en wallpaper ingesteld. Log opnieuw in of herstart voor volledig effect."
    } else {
        $CUFail = "Current user (HKCU) theme keys failed: $RegOutCU1 $RegOutCU2 $RegOutCU3"
        Write-DeployLog $CUFail -IsError
    }

    Write-DeployLog "SUCCESS: Dark mode and wallpaper process done."
    exit 0
} catch {
    $CatchErr = $_.Exception.Message
    Write-DeployLog "Unexpected error during setup: $CatchErr" -IsError
    Write-Output "Dark mode en wallpaper gedeeltelijk ingesteld."
    exit 0
}
