# WinDeploy Theme and Wallpaper Manager
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Sets Windows wallpaper and theme via registry and Windows API.

.DESCRIPTION
    Applies wallpaper and theme settings directly without opening the Settings app.

.PARAMETER WallpaperPath
    Path to wallpaper image. Default: Windows 11 dark wallpaper.

.PARAMETER Theme
    Theme preset: 'Dark', 'Light', 'Mixed', 'Inverted'. Default: 'Dark'

.PARAMETER AppsTheme
    Apps theme override: 'light' or 'dark'

.PARAMETER SystemTheme
    System theme override: 'light' or 'dark'

.EXAMPLE
    .\Set-Theme.ps1

.EXAMPLE
    .\Set-Theme.ps1 -WallpaperPath "C:\Custom\bg.jpg" -Theme Light

.NOTES
    Requires : Admin rights
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Set-Theme.log' -RequiredModules @('Logging','System') -RequireAdmin

# Define Windows API
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class WinAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public static void SetWallpaper(string path) {
        if (!SystemParametersInfo(20, 0, path, 0x01 | 0x02))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void BroadcastThemeChange() {
        IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
        IntPtr result;

        // Notify ImmersiveColorSet change
        SendMessageTimeout(HWND_BROADCAST, 0x001A, IntPtr.Zero, "ImmersiveColorSet", 2, 5000, out result);

        // Send theme changed message
        PostMessage(HWND_BROADCAST, 0x031A, IntPtr.Zero, IntPtr.Zero);
    }
}
'@ -ErrorAction SilentlyContinue

function Set-Theme {
    <#
    .SYNOPSIS
        Sets Windows light/dark theme.
    .DESCRIPTION
        Updates registry and notifies Windows of theme changes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Apps,
        [string]$System
    )

    $keyPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    if ($PSCmdlet.ShouldProcess("Windows Theme", "Set Apps=$Apps, System=$System")) {
        # Create registry key if needed
        if (!(Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }

        # Convert to registry values: 0=dark, 1=light
        $appsValue = if ($Apps -eq 'light') { 1 } else { 0 }
        $systemValue = if ($System -eq 'light') { 1 } else { 0 }

        # Write to registry
        Set-ItemProperty -Path $keyPath -Name 'AppsUseLightTheme' -Value $appsValue -Type DWord
        Set-ItemProperty -Path $keyPath -Name 'SystemUsesLightTheme' -Value $systemValue -Type DWord

        # Notify Windows of change
        [WinAPI]::BroadcastThemeChange()

        # Wait for changes to apply
        Start-Sleep -Milliseconds 500
    }
}

function Close-SettingsIfOpen {
    <#
    .SYNOPSIS
        Closes Settings app if running.
    #>
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Main execution
try {
    Write-Log "Applying wallpaper and theme configuration..." -Level Info

    # Fixed configuration values
    $WallpaperPath = "$env:WINDIR\Web\Wallpaper\Windows\img19.jpg"
    $AppsTheme = 'dark'
    $SystemTheme = 'dark'

    # Ensure Settings isn't running
    Close-SettingsIfOpen

    # Set wallpaper
    Write-UserMessage "  - Setting wallpaper to Windows default..." -Color Cyan
    Write-Log "Setting wallpaper: $WallpaperPath" -Level Info
    [WinAPI]::SetWallpaper($WallpaperPath)
    Write-UserMessage "  - Wallpaper applied" -Color Green

    # Apply dark theme
    Write-UserMessage "  - Configuring dark theme..." -Color Cyan
    Write-Log "Setting theme: Apps=$AppsTheme, System=$SystemTheme" -Level Info
    Set-Theme -Apps $AppsTheme -System $SystemTheme
    Write-UserMessage "  - Theme configured (active on next shell reload)" -Color Green

    Write-Log "Configuration applied successfully" -Level Success

    # Explicit successful exit
    exit 0

} catch {
    Write-UserMessage "  - Failed to apply theme: $($_.Exception.Message)" -Color Red
    Write-Log "Failed to apply configuration: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Complete-DeploymentScript
}
