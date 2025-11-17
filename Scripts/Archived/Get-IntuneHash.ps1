#requires -Version 5.1

<#
.SYNOPSIS
    Collects hardware hash for Intune/Autopilot enrollment.
.DESCRIPTION
    Collects the device's hardware hash and saves it to a CSV file.
#>

param(
    [string]$OutputPath,
    [switch]$Append,
    [string]$GroupTag,
    [switch]$Online
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges."
    exit 1
}

# Determine output path
if (-not $OutputPath) {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
        $desktopPath = $env:USERPROFILE
        if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
            $desktopPath = 'C:\Temp'
            if (-not (Test-Path $desktopPath)) {
                New-Item -Path $desktopPath -ItemType Directory -Force | Out-Null
            }
        }
    }
    $OutputPath = Join-Path $desktopPath 'HardwareHash.csv'
}

Write-Output "Collecting device hardware hash..."

# Check for Get-WindowsAutopilotInfo script
$scriptInstalled = Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue
if (-not $scriptInstalled) {
    Write-Output "Installing Get-WindowsAutopilotInfo..."
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope CurrentUser
        Write-Output "Installed successfully"
    } catch {
        Write-Error "Failed to install Get-WindowsAutopilotInfo"
        exit 1
    }
}

# Ensure the script path is in the environment PATH
$scriptPath = (Get-InstalledScript -Name Get-WindowsAutopilotInfo).InstalledLocation
if ($scriptPath -and -not ($env:Path -like "*$scriptPath*")) {
    $env:Path += ";$scriptPath"
}

# Build Get-WindowsAutopilotInfo command
$params = @{ OutputFile = $OutputPath }
if ($Append) { $params['Append'] = $true }
if ($GroupTag) { $params['GroupTag'] = $GroupTag }
if ($Online) {
    $params['Online'] = $true
    $params.Remove('OutputFile')
    Write-Output "Mode: Online upload to Intune"
}

# Collect hardware hash
try {
    if ($Online) {
        Get-WindowsAutopilotInfo @params
        Write-Output "Uploaded to Intune successfully"
    } else {
        Get-WindowsAutopilotInfo @params
        Write-Output "Saved to: $OutputPath"
    }

    $serial = (Get-CimInstance Win32_BIOS).SerialNumber
    $model = (Get-CimInstance Win32_ComputerSystem).Model
    $manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Output "Device: $manufacturer $model (S/N: $serial)"
} catch {
    Write-Error "Failed to collect hardware hash: $($_.Exception.Message)"
    exit 1
}