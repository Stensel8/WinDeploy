# ============================================================================
# Fix-Spotlight.ps1
# Re-enables Windows Spotlight on the lockscreen and desktop after deployment.
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-DeployLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [switch]$IsError
    )

    $logDir = 'C:\WinDeploy\Logs'
    if (-not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $scriptName = if ($MyInvocation.MyCommand.Name) {
        [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    } else {
        'Fix-Spotlight'
    }

    $logFile = Join-Path $logDir "$scriptName.log"

    $timeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[${timeStamp}] $Message"

    $line | Out-File -FilePath $logFile -Append -Encoding UTF8

    if ($IsError) {
        Write-Error $line
    } else {
        Write-Output $line
    }
}

try {
    Write-DeployLog '=== Fixing Windows Spotlight ==='

    # Remove possible policies that block desktop Spotlight
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableSpotlightCollectionOnDesktop" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -ErrorAction SilentlyContinue
    Write-DeployLog 'Removed blocking Spotlight policies'

    # ---------------------------------------------------------
    # 1. Registry: Enable Spotlight on lockscreen
    # ---------------------------------------------------------
    $regEntries = @(
        # PolicyManager – usually not strictly necessary, but can come into play
        @{
            Hive  = 'HKLM:'
            Path  = 'SOFTWARE\Microsoft\PolicyManager\current\device\Start'
            Name  = 'HideRecommendedSection'
            Type  = 'DWord'
            Value = 0
        },
        @{
            Hive  = 'HKLM:'
            Path  = 'SOFTWARE\Microsoft\PolicyManager\current\device\Education'
            Name  = 'IsEducationEnvironment'
            Type  = 'DWord'
            Value = 0
        },
        # Classic policy key
        @{
            Hive  = 'HKLM:'
            Path  = 'SOFTWARE\Policies\Microsoft\Windows\Explorer'
            Name  = 'HideRecommendedSection'
            Type  = 'DWord'
            Value = 0
        },
        # ContentDeliveryManager for Spotlight
        @{
            Hive  = 'HKCU:'
            Path  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            Name  = 'ContentDeliveryAllowed'
            Type  = 'DWord'
            Value = 1
        },
        @{
            Hive  = 'HKCU:'
            Path  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            Name  = 'RotatingLockScreenEnabled'
            Type  = 'DWord'
            Value = 1
        },
        @{
            Hive  = 'HKCU:'
            Path  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            Name  = 'RotatingLockScreenOverlayEnabled'
            Type  = 'DWord'
            Value = 1
        },
        @{
            Hive  = 'HKCU:'
            Path  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            Name  = 'RotatingLockScreenOverlayContentEnabled'
            Type  = 'DWord'
            Value = 1
        }
    )

    foreach ($entry in $regEntries) {
        $fullPath = Join-Path $entry.Hive $entry.Path

        if (-not (Test-Path -Path $fullPath)) {
            New-Item -Path $fullPath -Force | Out-Null
            Write-DeployLog "Created registry path: $fullPath"
        }

        try {
            Set-ItemProperty -Path $fullPath -Name $entry.Name -Value $entry.Value -Type $entry.Type -Force
            Write-DeployLog "Set $fullPath\$($entry.Name) to $($entry.Value)"
        } catch {
            Write-DeployLog "Failed to set $fullPath\$($entry.Name): $($_.Exception.Message)" -IsError
        }
    }

    # Reset ContentDeliveryManager keys that might block Spotlight
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "NoSpotlight" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayContentEnabled" -ErrorAction SilentlyContinue
    Write-DeployLog 'Removed blocking ContentDeliveryManager properties'

    # ---------------------------------------------------------
    # 2. Desktop Spotlight strings under HKCU\...\DesktopSpotlight
    # ---------------------------------------------------------
    Write-DeployLog 'Ensuring Desktop Spotlight registry keys...'

    $desktopSpotlightPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight'
    if (-not (Test-Path $desktopSpotlightPath)) {
        New-Item -Path $desktopSpotlightPath -Force | Out-Null
        Write-DeployLog "Created DesktopSpotlight path: $desktopSpotlightPath"
    }

    $desktopStrings = @(
        'RegistrationStatusCheck',
        'Rotation',
        'State',
        'UpdateTask',
        'UpdateTimer',
        'WallpaperRefresh'
    )

    foreach ($name in $desktopStrings) {
        try {
            if (-not (Get-ItemProperty -Path $desktopSpotlightPath -Name $name -ErrorAction SilentlyContinue)) {
                New-ItemProperty -Path $desktopSpotlightPath -Name $name -PropertyType String -Value '' -Force | Out-Null
                Write-DeployLog "Created DesktopSpotlight value: $name"
            } else {
                Write-DeployLog "DesktopSpotlight value already exists: $name"
            }
        } catch {
            Write-DeployLog "Failed to ensure DesktopSpotlight value ${name}: $($_.Exception.Message)" -IsError
        }
    }

    # Optionally disable the policy to turn off all Spotlight features
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
    $prop = Get-ItemProperty -Path $policyPath -Name "DisableSpotlightFeatures" -ErrorAction SilentlyContinue
    if ($prop -and $prop.DisableSpotlightFeatures -ne 0) {
        Set-ItemProperty -Path $policyPath -Name "DisableSpotlightFeatures" -Value 0 -Type DWord
        Write-DeployLog 'Disabled DisableSpotlightFeatures policy'
    }

    # ---------------------------------------------------------
    # 3. Re-register ContentDeliveryManager (Spotlight component)
    # ---------------------------------------------------------
    Write-DeployLog 'Re-registering ContentDeliveryManager package...'
    try {
        Get-AppxPackage -AllUsers *ContentDeliveryManager* | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $_.InstallLocation 'AppXManifest.xml')
        }
        Write-DeployLog 'Re-registered ContentDeliveryManager package'
    } catch {
        Write-DeployLog "Failed to re-register ContentDeliveryManager: $($_.Exception.Message)" -IsError
    }

    # ---------------------------------------------------------
    # 4. IrisService folderstructuur voor Desktop Spotlight
    # ---------------------------------------------------------
    Write-DeployLog 'Ensuring IrisService folder structure...'
    $localCachePath = Join-Path $env:USERPROFILE 'AppData\Local\Packages\Microsoft.Windows.Client.CBS_cw5n1h2txyewy\LocalCache'
    $irisPath       = Join-Path $localCachePath 'Microsoft\IrisService'

    try {
        if (-not (Test-Path $irisPath)) {
            New-Item -ItemType Directory -Path $irisPath -Force | Out-Null
            Write-DeployLog 'Created IrisService folder structure'
        } else {
            Write-DeployLog 'IrisService folder structure already exists'
        }
    } catch {
        Write-DeployLog "Failed to create IrisService folders: $($_.Exception.Message)" -IsError
    }

    # ---------------------------------------------------------
    # 5. Spotlight assets cache leegmaken
    # ---------------------------------------------------------
    Write-DeployLog 'Cleaning Spotlight assets and cache...'
    $assetsPath = Join-Path $env:USERPROFILE 'AppData\Local\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\LocalState\Assets'

    try {
        if (Test-Path $assetsPath) {
            Remove-Item -Path (Join-Path $assetsPath '*') -Recurse -Force
            Write-DeployLog 'Cleaned Spotlight assets'
        } else {
            Write-DeployLog 'Assets path not found'
        }
    } catch {
        Write-DeployLog "Failed to clean Spotlight assets: $($_.Exception.Message)" -IsError
    }

    # ---------------------------------------------------------
    # 6. Explorer herstarten + policies refresh (optioneel)
    # ---------------------------------------------------------
    try {
        Write-DeployLog 'Restarting Explorer...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } catch {
        Write-DeployLog "Failed to restart Explorer: $($_.Exception.Message)" -IsError
    }

    try {
        Write-DeployLog 'Refreshing user policies and system parameters...'
        gpupdate /target:user /force | Out-Null
        rundll32.exe user32.dll,UpdatePerUserSystemParameters ,1 ,True
    } catch {
        Write-DeployLog "Failed to refresh policies/system parameters: $($_.Exception.Message)" -IsError
    }

    # ---------------------------------------------------------
    # 7. Success message
    # ---------------------------------------------------------
    $successMsg = "SUCCESS: Windows Spotlight has been re-enabled for both lock screen and desktop. Set your lock screen background to 'Windows Spotlight' in Settings > Personalization. A logoff or restart may be required."
    Write-DeployLog $successMsg
    exit 0
}
catch {
    $errMsg = $_.Exception.Message
    Write-DeployLog "Error: $errMsg" -IsError
    Write-Error 'Spotlight fix failed.'
    exit 1
}
