# WinDeploy Intune Hardware Hash Collector
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1

<#
.SYNOPSIS
    Collects hardware hash for Intune/Autopilot enrollment.

.DESCRIPTION
    Collects device hardware hash and saves to CSV on Desktop. Can run during
    OOBE (Shift+F10) or on deployed systems. Installs required module if needed.

.PARAMETER OutputPath
    Custom output path for CSV file. Default: Desktop\HardwareHash.csv

.PARAMETER Append
    Appends to existing CSV instead of overwriting.

.PARAMETER GroupTag
    Group tag for Autopilot profile assignment.

.PARAMETER Online
    Uploads hardware hash directly to Intune (requires authentication).

.EXAMPLE
    .\Get-IntuneHash.ps1

.EXAMPLE
    .\Get-IntuneHash.ps1 -Append

.EXAMPLE
    .\Get-IntuneHash.ps1 -GroupTag "CompanyName-Laptops"

.EXAMPLE
    .\Get-IntuneHash.ps1 -Online -GroupTag "CompanyName-Laptops"

.NOTES
    Requires : PowerShell 5.1+

    This script can be run:
    - During OOBE: Press Shift+F10, type 'powershell', then run script from USB (D:\)
    - On deployed system: Run from Desktop or any location

    For OOBE usage:
    1. Boot new device
    2. At language selection screen, press Shift+F10
    3. Type: powershell
    4. Insert USB drive (usually D:)
    5. Run: D:\Get-IntuneHash.ps1
    6. For multiple devices: D:\Get-IntuneHash.ps1 -Append
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Append,

    [Parameter()]
    [string]$GroupTag,

    [Parameter()]
    [switch]$Online
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ADMINISTRATOR PRIVILEGES REQUIRED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This script requires administrator privileges to collect hardware hash." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please run this script as Administrator:" -ForegroundColor Cyan
    Write-Host "  1. Right-click PowerShell" -ForegroundColor Gray
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "  3. Navigate to script location and run again" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Determine output path
if (-not $OutputPath) {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if (-not $desktopPath -or -not (Test-Path $desktopPath)) {
        # Fallback for OOBE or when desktop not available
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

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INTUNE HARDWARE HASH COLLECTOR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for Get-WindowsAutopilotInfo script
Write-Host "  - Checking for Autopilot tools..." -ForegroundColor Cyan

$scriptInstalled = Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue

if (-not $scriptInstalled) {
    Write-Host "  - Tools not found, installing..." -ForegroundColor Yellow

    try {
        # Ensure NuGet provider is installed
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        # Set PSGallery as trusted to avoid prompts
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope CurrentUser

        Write-Host "  - Autopilot tools installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to install Get-WindowsAutopilotInfo script" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure you have internet connectivity" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Manual installation:" -ForegroundColor Yellow
        Write-Host "  Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope CurrentUser" -ForegroundColor Gray
        exit 1
    }
} else {
    Write-Host "  - Autopilot tools ready" -ForegroundColor Green
}

# Ensure the script path is in the environment PATH
$scriptPath = (Get-InstalledScript -Name Get-WindowsAutopilotInfo).InstalledLocation
if ($scriptPath -and -not ($env:Path -like "*$scriptPath*")) {
    $env:Path += ";$scriptPath"
}

# Build Get-WindowsAutopilotInfo command
$params = @{
    OutputFile = $OutputPath
}

if ($Append) {
    $params['Append'] = $true
}

if ($GroupTag) {
    $params['GroupTag'] = $GroupTag
}

if ($Online) {
    $params['Online'] = $true
    $params.Remove('OutputFile')  # Online mode doesn't use OutputFile
    Write-Host "  - Mode: Online upload to Intune" -ForegroundColor Cyan
}

# Collect hardware hash
Write-Host "  - Collecting device hardware hash..." -ForegroundColor Cyan

try {
    if ($Online) {
        # Online upload
        Get-WindowsAutopilotInfo @params
        Write-Host "  - Uploaded to Intune successfully" -ForegroundColor Green

    } else {
        # Save to file
        Get-WindowsAutopilotInfo @params
        Write-Host "  - Saved to: $OutputPath" -ForegroundColor Green
    }

    # Display device information
    $serial = (Get-CimInstance Win32_BIOS).SerialNumber
    $model = (Get-CimInstance Win32_ComputerSystem).Model
    $manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Host "  - Device: $manufacturer $model (S/N: $serial)" -ForegroundColor Gray
    Write-Host ""

} catch {
    Write-Host "  - Failed to collect hardware hash" -ForegroundColor Red
    Write-Host "  - Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
