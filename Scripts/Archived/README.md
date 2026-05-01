# Archived Scripts

Not part of the main deployment sequence. Kept as reference implementations, one-off utilities, or environment-specific scripts.

## Scripts

- `Fix-Spotlight.ps1`: Restores Windows Spotlight by clearing blocking registry policies.
- `Get-InstalledSoftware.ps1`: Collects a software inventory from the registry and AppX packages.
- `Get-IntuneHash.ps1`: Exports the device hardware hash to CSV for Intune/Autopilot enrollment.
- `Install-NetworkPrinter.ps1`: **Placeholder/example.** Written for a Konica Minolta C360i. Adapt driver paths, model strings, and defaults for your own printer.
- `Uninstall-NetworkPrinter.ps1`: **Placeholder/example.** Counterpart to the install script. Adapt for your own printer model.

Not called by `Deploy.ps1` or `Start.ps1`.
