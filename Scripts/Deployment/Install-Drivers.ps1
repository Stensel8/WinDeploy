# ============================================================================
# Install-Drivers.ps1
# Installs vendor-specific driver update tools and updates drivers.
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

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

    # Get script directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

    # Get system manufacturer and model
    $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $manufacturer = $systemInfo.Manufacturer.ToLower()
    $model = $systemInfo.Model

    Write-DeployLog "System: $manufacturer $model"

    # Load supported devices
    $supportedDellDevices = @()
    $supportedHPDevices = @()

    $version = "testing"

    $dellPath = "C:\WinDeploy\Download\SupportedDellDevices.json"
    $hpPath = "C:\WinDeploy\Download\SupportedHPDevices.json"

    if (!(Test-Path $dellPath)) {
        $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$version/Docs/SupportedDellDevices.json"
        try {
            Invoke-WebRequest -Uri $url -OutFile $dellPath -UseBasicParsing -ErrorAction Stop
            Write-DeployLog "Downloaded SupportedDellDevices.json"
        } catch {
            Write-Warning "Failed to download SupportedDellDevices.json"
        }
    }

    if (!(Test-Path $hpPath)) {
        $url = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$version/Docs/SupportedHPDevices.json"
        try {
            Invoke-WebRequest -Uri $url -OutFile $hpPath -UseBasicParsing -ErrorAction Stop
            Write-DeployLog "Downloaded SupportedHPDevices.json"
        } catch {
            Write-Warning "Failed to download SupportedHPDevices.json"
        }
    }

    if (Test-Path $dellPath) {
        try {
            $supportedDellDevices = Get-Content $dellPath -Raw | ConvertFrom-Json | Where-Object { -not $_.StartsWith("//") }
            Write-DeployLog "Loaded Dell list from $dellPath"
        } catch {
            Write-Warning "Failed to load Dell device list"
        }
    }

    if (Test-Path $hpPath) {
        try {
            $supportedHPDevices = Get-Content $hpPath -Raw | ConvertFrom-Json | Where-Object { -not $_.StartsWith("//") }
            Write-DeployLog "Loaded HP list from $hpPath"
        } catch {
            Write-Warning "Failed to load HP device list"
        }
    }

    # Check if supported
    $isSupported = $false
    if ($manufacturer -like "*dell*") {
        Write-DeployLog "Checking Dell support..."
        foreach ($pattern in $supportedDellDevices) {
            if ($model -like "*$pattern*") {
                $isSupported = $true
                Write-DeployLog "Matched pattern: $pattern"
                break
            }
        }
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        Write-DeployLog "Checking HP support..."
        foreach ($pattern in $supportedHPDevices) {
            if ($model -like "*$pattern*") {
                $isSupported = $true
                Write-DeployLog "Matched pattern: $pattern"
                break
            }
        }
    }

    if (-not $isSupported) {
        Write-Warning "Skipped: Unsupported device"
        exit 0
    }

    if ($manufacturer -like "*dell*") {
        Write-DeployLog "Supported Dell system detected. Installing Dell Command Update..."
        try {
            winget install --id Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements
            Write-DeployLog "Dell Command Update installed."

            # Find DCU
            $dcuPaths = @(
                "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
                "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
            )
            $dcu = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

            if ($dcu) {
                Write-DeployLog "Scanning for driver updates..."
                $scanOutput = & $dcu /scan 2>&1
                $scanExitCode = $LASTEXITCODE
                if ($scanOutput) {
                    Write-DeployLog ($scanOutput -join "`n")
                }
                if ($scanExitCode -eq 0) {
                    Write-DeployLog "Installing driver updates..."
                    $applyResult = Start-Process $dcu -ArgumentList "/applyUpdates", "/reboot=no", "/silent" -Wait -PassThru -NoNewWindow -RedirectStandardOutput $null -RedirectStandardError $null
                    if ($applyResult.ExitCode -eq 0 -or $applyResult.ExitCode -eq 1 -or $applyResult.ExitCode -eq 2 -or $applyResult.ExitCode -eq 5 -or $applyResult.ExitCode -eq 500) {
                        Write-DeployLog "Driver updates completed."
                    } else {
                        Write-DeployLog "Driver updates failed with exit code $($applyResult.ExitCode)."
                    }
                } elseif ($scanExitCode -eq 500) {
                    Write-DeployLog "No driver updates available."
                } else {
                    Write-DeployLog "Scan failed with exit code $scanExitCode."
                }
            } else {
                Write-DeployLog "DCU executable not found after installation."
            }
        } catch {
            Write-DeployLog "Failed to install or run Dell Command Update"
            Write-Warning "Dell driver installation failed. Check logs for details."
        }
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        Write-DeployLog "HP system detected. Installing HP Client Management Script Library..."
        try {
            # Install HPCMSL module if not present
            if (-not (Get-Module -Name HPCMSL -ListAvailable)) {
                Install-Module -Name HPCMSL -Force -AllowClobber -ErrorAction Stop
            }
            Import-Module HPCMSL -ErrorAction Stop
            Write-DeployLog "HPCMSL installed and imported."

            # Use HPCMSL to update the device
            Write-DeployLog "Running HP device updates via HPCMSL..."
            $updateResult = Update-HPDevice -All -Yes -ErrorAction Stop
            if ($updateResult) {
                Write-DeployLog "HP device updates completed."
            } else {
                Write-Warning "HP device updates failed or no updates available."
            }
        } catch {
            Write-DeployLog "Failed to install or run HPCMSL updates: $_"
            Write-Warning "HP driver installation failed. Check logs for details."
        }
    } else {
        Write-Warning "Unsupported manufacturer for automatic driver installation."
    }

    Write-DeployLog "SUCCESS: Driver installation done."
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "Driver installation partial - continuing."
    exit 0
}
