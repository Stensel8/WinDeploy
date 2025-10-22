# WinDeploy Software Inventory Tool
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1

<#
.SYNOPSIS
    Inventories all installed software on the system.

.DESCRIPTION
    Queries traditional Win32 applications (via registry) and modern Store apps
    (via AppX packages) to provide a comprehensive software inventory.

.EXAMPLE
    .\Get-InstalledSoftware.ps1

.NOTES
    Requires : PowerShell 5.1+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# Import required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'Get-InstalledSoftware.log'
Initialize-Script

try {
    $allSoftware = @()

    # Get Win32 apps from registry
    Write-Log "Scanning registry for Win32 applications..." -Level Info

    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $win32Apps = foreach ($path in $registryPaths) {
        Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSObject.properties.Name -contains 'DisplayName' -and
            $_.DisplayName -and
            ($_.DisplayName -notlike "*Update*" -and $_.DisplayName -notlike "KB*")
        } |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.DisplayName
                Version = if ($_.PSObject.Properties.Name -contains 'DisplayVersion') { $_.DisplayVersion } else { $null }
                Publisher = if ($_.PSObject.Properties.Name -contains 'Publisher') { $_.Publisher } else { $null }
                InstallDate = if ($_.PSObject.Properties.Name -contains 'InstallDate' -and $_.InstallDate) {
                    try {
                        [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
                    } catch {
                        $_.InstallDate
                    }
                } else { $null }
                Type = "Win32"
                Location = if ($_.PSObject.Properties.Name -contains 'InstallLocation') { $_.InstallLocation } else { $null }
            }
        }
    }

    $allSoftware += $win32Apps
    Write-Log "Found $($win32Apps.Count) Win32 applications" -Level Info

    # Get Store/UWP apps
    Write-Log "Scanning for Store/UWP applications..." -Level Info

    $storeApps = Get-AppxPackage -AllUsers |
    Where-Object {
        $_.Name -and
        $_.Name -notlike "*Update*"
    } |
    ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Version = if ($_.PSObject.Properties.Name -contains 'Version') { $_.Version } else { $null }
            Publisher = if ($_.PSObject.Properties.Name -contains 'Publisher') { $_.Publisher } else { $null }
            InstallDate = if ($_.PSObject.Properties.Name -contains 'InstallDate' -and $_.InstallDate) {
                $_.InstallDate.ToString("yyyy-MM-dd")
            } else { $null }
            Type = "Store"
            Location = if ($_.PSObject.Properties.Name -contains 'InstallLocation') { $_.InstallLocation } else { $null }
        }
    }

    $allSoftware += $storeApps
    Write-Log "Found $($storeApps.Count) Store applications" -Level Info

    # Remove duplicates
    $allSoftware = $allSoftware | Sort-Object Name, Version -Unique

    Write-Log "Total unique applications: $($allSoftware.Count)" -Level Success

    # Display results
    $storeList = @($allSoftware | Where-Object { $_.Type -eq "Store" } | Sort-Object Name)
    $win32List = @($allSoftware | Where-Object { $_.Type -eq "Win32" } | Sort-Object Name)

    # Display summary
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "Type   Count" -ForegroundColor White
    Write-Host "----   -----" -ForegroundColor White
    Write-Host "Store  $($storeList.Count)" -ForegroundColor White
    Write-Host "Win32  $($win32List.Count)" -ForegroundColor White
    Write-Host "Total apps: $($allSoftware.Count)`n" -ForegroundColor Green

    # Display Store apps
    if ($storeList.Count -gt 0) {
        Write-Host "`n=== STORE APPLICATIONS ===" -ForegroundColor Cyan
        Write-Host ""
        foreach ($app in $storeList) {
            Write-Host "Name        : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Name)"
            Write-Host "Version     : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Version)"
            Write-Host "Publisher   : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Publisher)"
            Write-Host "InstallDate : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.InstallDate)"
            Write-Host "Type        : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Type)"
            Write-Host "Location    : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Location)"
            Write-Host ""
        }
    }

    # Display Win32 apps
    if ($win32List.Count -gt 0) {
        Write-Host "`n=== WIN32 APPLICATIONS ===" -ForegroundColor Cyan
        Write-Host ""
        foreach ($app in $win32List) {
            Write-Host "Name        : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Name)"
            Write-Host "Version     : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Version)"
            Write-Host "Publisher   : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Publisher)"
            Write-Host "InstallDate : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.InstallDate)"
            Write-Host "Type        : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Type)"
            Write-Host "Location    : " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Location)"
            Write-Host ""
        }
    }

} catch {
    Write-Log "Error: $_" -Level Error
} finally {
    Complete-Script
}
