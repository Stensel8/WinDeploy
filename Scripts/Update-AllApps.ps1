<#PSScriptInfo

.AUTHOR Sten Tijhuis

.COMPANYNAME WinDeploy

.TAGS PowerShell Windows WinGet Updates Applications Maintenance

.PROJECTURI https://github.com/Stensel8/WinDeploy

#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Updates all applications via WinGet package manager.

.DESCRIPTION
    Scans for available application updates using Windows Package Manager (WinGet)
    and installs them automatically.

.EXAMPLE
    .\Update-AllApps.ps1

.NOTES
    Version      : See VERSION file in repository root
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Requires     : Admin rights, WinGet installed

.LINK
    Project Site: https://github.com/Stensel8/WinDeploy
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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
Import-Module (Join-Path $utilitiesPath 'Registry.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'Winget.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'Deployment.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'Update-AllApps.log'
Initialize-Script -RequireAdmin

try {
    # Ensure WinGet availability
    $wg = Test-WinGetFunctional
    $wingetPath = $wg.Path

    # Get available updates
    Write-Log "Checking for available updates..." -Level Info
    $upgradeOutput = & $wingetPath upgrade --include-unknown 2>&1

    # Parse output for updates
    $updates = @()
    $parsing = $false

    foreach ($line in $upgradeOutput) {
        # Start parsing after the header line
        if ($line -match '^-+\s+-+') {
            $parsing = $true
            continue
        }

        if (-not $parsing) { continue }
        if ($line -match '^\d+ upgrades? available') { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Parse update line (Name, Id, Current Version, Available Version)
        $parts = $line -split '\s{2,}'
        if ($parts.Count -ge 4) {
            $id = $parts[1].Trim()

            $updates += [PSCustomObject]@{
                Name = $parts[0].Trim()
                Id = $id
                CurrentVersion = $parts[2].Trim()
                AvailableVersion = $parts[3].Trim()
            }
        }
    }

    if ($updates.Count -eq 0) {
        Write-Log "No updates available" -Level Success
        Set-IntuneSuccess -AppName 'UpdateAllApps' -Version (Get-Date -Format 'yyyy.MM.dd')
        exit 0
    }

    Write-Log "Found $($updates.Count) available updates:" -Level Info
    foreach ($update in $updates) {
        Write-Log "  $($update.Name): $($update.CurrentVersion) → $($update.AvailableVersion)" -Level Info
    }

    # Install updates
    Write-Log "Starting updates..." -Level Info
    $success = 0
    $failed = 0

    foreach ($update in $updates) {
        Write-Log "Updating $($update.Name)..." -Level Info

        $result = Invoke-WithRetry -ScriptBlock {
            $proc = Start-Process $wingetPath -ArgumentList @(
                'upgrade',
                '--id', $update.Id,
                '--silent',
                '--accept-package-agreements',
                '--accept-source-agreements'
            ) -Wait -PassThru -NoNewWindow

            if ($proc.ExitCode -ne 0) {
                throw "Exit code: $($proc.ExitCode)"
            }
        } -MaxAttempts 2 -DelaySeconds 3

        if ($null -eq $result -or $result -eq $true) {
            Write-Log "  ✓ Updated successfully" -Level Success
            $success++
        } else {
            Write-Log "  ✗ Update failed" -Level Error
            $failed++
        }
    }

    # Summary
    Write-Log "Update complete: $success succeeded, $failed failed" -Level $(if ($failed -eq 0) { 'Success' } else { 'Warning' })

    # Record Intune success if all updates succeeded
    if ($failed -eq 0) {
        Set-IntuneSuccess -AppName 'UpdateAllApps' -Version (Get-Date -Format 'yyyy.MM.dd')
    }

    exit $(if ($failed -gt 0) { 1 } else { 0 })

} catch {
    Write-Log "Update process failed: $_" -Level Error
    exit 1
} finally {
    Complete-Script
}

