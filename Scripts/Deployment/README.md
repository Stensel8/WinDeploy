# Deployment Scripts

This folder contains PowerShell scripts used for automating various deployment tasks in the WinDeploy project.

## Scripts

- `Install-Applications.ps1`: Installs required applications.
- `Install-Drivers.ps1`: Installs device drivers.
- `Install-WindowsUpdates.ps1`: Installs Windows updates.
- `Remove-Bloat.ps1`: Removes bloatware.
- `Set-HostName.ps1`: Sets the hostname.
- `Set-Theme.ps1`: Configures the theme.

## Usage

### Running Individually

Each script can be run separately by executing it directly in PowerShell:

```powershell
.\Install-Applications.ps1
```

### Running All Scripts

To run all deployment scripts in sequence, execute `Start.ps1` from the root of the project:

```powershell
# From the project root
.\Scripts\Start.ps1
```

Note: `Start.ps1` runs the scripts in a specific order: Drivers, Applications, Bloatware Removal, Theme, Windows Updates. `Set-HostName.ps1` is not included in the automated sequence.