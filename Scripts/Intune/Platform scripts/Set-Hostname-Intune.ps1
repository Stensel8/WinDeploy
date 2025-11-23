# ============================================================================
# Set-Hostname-Intune.ps1
# Sets computer hostname based on BIOS serial number (last 5 characters)
# Returns exit code 3010 to signal reboot required for OOBE/Intune
# Compatible with: Intune Platform Scripts | Local Admin (SYSTEM context)
# ============================================================================

# Get BIOS serial number
$serial = (Get-CimInstance Win32_BIOS).SerialNumber

# Build new hostname with prefix PC- plus last 5 characters of serial
$newName = 'PC-{0}' -f $serial.Substring($serial.Length - 5)

# Get current computer name
$currentName = (Get-CimInstance Win32_ComputerSystem).Name

if ($currentName -ne $newName) {
    # Rename the computer to the new hostname
    Rename-Computer -NewName $newName -Force
    # Exit with code 3010 to indicate reboot required
    exit 3010
} else {
    # Hostname already set correctly, exit with success
    exit 0
}
