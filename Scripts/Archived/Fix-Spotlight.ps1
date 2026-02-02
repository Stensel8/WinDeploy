# Complete script to activate Windows Spotlight for Lock Screen and Desktop
# Based on registry adjustments, package re-registration and policy resets
# Run as Administrator; restart after execution for full effect

# Step 1: Remove blocking policies (CloudContent)
Write-Host "Step 1: Removing blocking policies..." -ForegroundColor Green
$policyPath = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
if (Test-Path $policyPath) {
    Remove-ItemProperty -Path $policyPath -Name "DisableSpotlightCollectionOnDesktop" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $policyPath -Name "DisableWindowsSpotlightFeatures" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $policyPath -Name "TurnOffAllWindowsSpotlightFeatures" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $policyPath -Name "ConfigureWindowsSpotlightOnLockScreen" -ErrorAction SilentlyContinue
    Write-Host "Policies removed or reset." -ForegroundColor Yellow
} else {
    Write-Host "No blocking policies found." -ForegroundColor Cyan
}

# Step 2: Create DesktopSpotlight registry keys if they are missing
Write-Host "Step 2: Creating DesktopSpotlight keys..." -ForegroundColor Green
$desktopSpotlightPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\DesktopSpotlight"
if (-not (Test-Path $desktopSpotlightPath)) {
    New-Item -Path $desktopSpotlightPath -Force | Out-Null
    Write-Host "DesktopSpotlight folder created." -ForegroundColor Yellow
}
$values = @("RegistrationStatusCheck", "Rotation", "State", "UpdateTask", "UpdateTimer", "WallpaperRefresh")
foreach ($val in $values) {
    if (-not (Get-ItemProperty -Path $desktopSpotlightPath -Name $val -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $desktopSpotlightPath -Name $val -PropertyType String -Value "" -Force | Out-Null
        Write-Host "Key '$val' created." -ForegroundColor Yellow
    }
}

# Step 3: Reset and activate ContentDeliveryManager keys
Write-Host "Step 3: Resetting ContentDeliveryManager..." -ForegroundColor Green
$contentPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Remove-ItemProperty -Path $contentPath -Name "NoSpotlight" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $contentPath -Name "NoRotatingLockScreen" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $contentPath -Name "RotatingLockScreenOverlayEnabled" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $contentPath -Name "RotatingLockScreenOverlayContentEnabled" -ErrorAction SilentlyContinue
# Activate
Set-ItemProperty -Path $contentPath -Name "ContentDeliveryAllowed" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $contentPath -Name "RotatingLockScreenEnabled" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $contentPath -Name "RotatingLockScreenOverlayEnabled" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $contentPath -Name "RotatingLockScreenOverlayContentEnabled" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $contentPath -Name "SubscribedContent-338389Enabled" -Value 1 -Type DWord -Force  # For desktop Spotlight
Write-Host "ContentDeliveryManager activated." -ForegroundColor Yellow

# Step 4: Re-register Spotlight package (for lockscreen and desktop)
Write-Host "Step 4: Re-registering Spotlight package..." -ForegroundColor Green
Get-AppxPackage -allusers Microsoft.Windows.ContentDeliveryManager | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
Write-Host "Package registered." -ForegroundColor Yellow

# Step 5: Optional policy-check and reset (if DisableSpotlightFeatures exists, set to 0)
Write-Host "Step 5: Extra policy-check..." -ForegroundColor Green
if ((Get-ItemProperty -Path $policyPath -Name "DisableSpotlightFeatures" -ErrorAction SilentlyContinue)) {
    Set-ItemProperty -Path $policyPath -Name "DisableSpotlightFeatures" -Value 0 -Type DWord -Force
    Write-Host "DisableSpotlightFeatures disabled." -ForegroundColor Yellow
}

# Step 6: Restart Explorer to apply changes
Write-Host "Step 6: Restarting Explorer..." -ForegroundColor Green
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "Script completed! Log out/in or restart for full effect. Check Settings > Personalization > Background." -ForegroundColor Green
