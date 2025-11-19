# Deployment Scripts

This folder contains PowerShell scripts used for automating various deployment tasks in the WinDeploy project.

## Scripts

- `Harden-Windows.ps1`: Applies security hardenings including AutoRun disable.
- `Install-Applications.ps1`: Installs required applications via WinGet.
- `Install-Drivers.ps1`: Installs device drivers for Dell/HP systems.
- `Install-RMMAgent.ps1`: Installs RMM agent from USB or download.
- `Install-WindowsUpdates.ps1`: Installs Windows updates.
- `Remove-Bloat.ps1`: Removes bloatware applications.
- `Set-HostName.ps1`: Sets the device hostname (optional, not in automated sequence).
- `Set-Theme.ps1`: Configures the system theme to dark mode.

## Usage

### Running Individually

Each script can be run separately. If you encounter execution policy restrictions, bypass it for the current session only (this does not permanently change security settings):

```powershell
# Bypass execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass

# Run the script
.\Install-Applications.ps1
```

### Running All Scripts

To run all deployment scripts in sequence, execute `Start.ps1` from the root of the project:

```powershell
# From the project root
.\Scripts\Start.ps1
```

Note: `Start.ps1` runs the scripts in this order: Drivers, RMM Agent, Windows Hardening, Applications, Bloatware Removal, Theme, Hostname, Windows Updates.