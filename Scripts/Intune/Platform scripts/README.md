# Intune Platform Scripts

PowerShell scripts for deployment as **Intune Platform Scripts**. Run in the SYSTEM context during or after enrollment.

## Scripts

- `Set-Hostname-Intune.ps1`: Renames the device to `PC-XXXXX` using the last 5 characters of the BIOS serial number. Returns exit code `3010` to trigger a reboot via Intune.
- `Skip-OOBEPrivacy-Intune.ps1`: Suppresses OOBE privacy screens and sets privacy defaults in the registry.

## Deploying via Intune

1. Go to **Devices > Scripts and remediations > Platform scripts**.
2. Upload the `.ps1` file.
3. Set **Run this script using the logged-on credentials** to **No**.
4. Assign to the appropriate device group.

Scripts are idempotent and do not depend on the main WinDeploy deployment sequence.
