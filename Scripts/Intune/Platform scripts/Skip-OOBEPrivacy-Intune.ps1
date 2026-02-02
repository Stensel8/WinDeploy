# ============================================================================
# Skip-OOBEPrivacy-Intune.ps1
# Skips OOBE privacy questions and sets privacy defaults
# Compatible with: Intune Platform Scripts | Local Admin (SYSTEM context)
# ============================================================================

# Set Registry paths as variables
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"
$registryPath2 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"

#Define Settings and Toggles to modify
$Name1 = "DisablePrivacyExperience"
$Name2 = "DisableVoice"
$Name3 = "PrivacyConsentStatus"
$Name4 = "Protectyourpc"
$Name5 = "HideEULAPage"
$Name6 = "EnableFirstLogonAnimation"

Write-Output "Setting OOBE privacy registry keys"

New-ItemProperty -Path $registryPath -Name $name1 -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $registryPath -Name $name2 -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $registryPath -Name $name3 -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $registryPath -Name $name4 -Value 3 -PropertyType DWord -Force
New-ItemProperty -Path $registryPath -Name $name5 -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $registryPath2 -Name $name6 -Value 1 -PropertyType DWord -Force

Write-Output "OOBE privacy settings configured"

exit 0
