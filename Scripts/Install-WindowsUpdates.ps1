<#PSScriptInfo

.AUTHOR Sten Tijhuis

.COMPANYNAME WinDeploy

.TAGS PowerShell Windows WindowsUpdate PSWindowsUpdate

.PROJECTURI https://github.com/Stensel8/WinDeploy

#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs all available Windows Updates automatically using PSWindowsUpdate module.

.DESCRIPTION
    Downloads and installs all available Windows Updates. Designed for automated deployment after OOBE.

.EXAMPLE
    .\Install-WindowsUpdates.ps1
    Installs all available updates.

.NOTES
    Version      : See VERSION file in repository root
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Requires     : PowerShell 5.1+, Admin rights
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve Utilities path and import only required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder in any expected location"; exit 1 }

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
$systemModule = Join-Path $utilitiesPath 'System.psm1'
if (-not (Test-Path $loggingModule)) { Write-Error "Logging.psm1 not found in $utilitiesPath"; exit 1 }
if (-not (Test-Path $systemModule)) { Write-Error "System.psm1 not found in $utilitiesPath"; exit 1 }
Import-Module $loggingModule -Force -Global
Import-Module $systemModule -Force -Global
Start-EmergencyTranscript -LogName 'Install-WindowsUpdates.log'

# Verify required functions are available
if (-not (Get-Command Initialize-Script -ErrorAction SilentlyContinue)) {
    Write-Error "Initialize-Script function not available after importing modules"
    exit 1
}
if (-not (Get-Command Complete-Script -ErrorAction SilentlyContinue)) {
    Write-Error "Complete-Script function not available after importing modules"
    exit 1
}

Initialize-Script -RequireAdmin

# Set execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Trust PSGallery to avoid prompts (best-effort)
try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { Write-Verbose "Failed to trust PSGallery: $($_.Exception.Message)" }

# Install NuGet provider if needed (required for PowerShell Gallery modules)
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    } catch {
        Write-Log "Failed to install NuGet provider: $($_.Exception.Message)" -Level Warning
    }
}

# Install PSWindowsUpdate module if not present
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    try {
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -ErrorAction Stop
        Write-Log "Installed PSWindowsUpdate module" -Level Info
    } catch {
        Write-Log "Failed to install PSWindowsUpdate module: $($_.Exception.Message)" -Level Error
        exit 1
    }
}

# Load PSWindowsUpdate module
Import-Module PSWindowsUpdate -Force

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  WINDOWS UPDATE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check Windows Update service
    Write-Host "Step 1: Verifying Windows Update service..." -ForegroundColor Cyan
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($wuService.Status -ne 'Running') {
        Write-Log "Windows Update service not running - starting it..." -Level Info
        try {
            Start-Service -Name wuauserv -ErrorAction Stop
            Start-Sleep -Seconds 3
            Write-Host "  - Service status: STARTED" -ForegroundColor Green
        } catch {
            Write-Log "Failed to start Windows Update service: $($_.Exception.Message)" -Level Warning
            Write-Host "  - Service status: FAILED TO START" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  - Service status: RUNNING" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Step 2: Scanning for available updates..." -ForegroundColor Cyan
    Write-Log "Scanning for Windows Updates (including Microsoft Update catalog)..." -Level Info
    Write-Host "  - Contacting update servers (this may take a moment)..." -ForegroundColor Gray

    # Use MicrosoftUpdate to get all updates including drivers and Microsoft products
    # Add verbose output to help diagnose scan issues
    try {
        $updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose -ErrorAction Stop
    } catch {
        Write-Log "Initial scan failed: $($_.Exception.Message). Retrying with Windows Update only..." -Level Warning
        Write-Host "  - Initial scan failed, retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $updates = Get-WindowsUpdate -Verbose -ErrorAction Stop
    }

    # Filter out empty or invalid updates
    $updates = $updates | Where-Object { $_.Title -and $_.Title.Trim() -ne '' }

    if (-not $updates -or $updates.Count -eq 0) {
        Write-Host ""
        Write-Host "  - Scan result: NO UPDATES AVAILABLE" -ForegroundColor Green
        Write-Host ""
        Write-Host "System is up to date!" -ForegroundColor Green
        Write-Log "No updates available." -Level Success
        Complete-Script
        exit 0
    }

    Write-Host ""
    Write-Host "  - Found: $($updates.Count) update(s)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Updates to install:" -ForegroundColor White
    foreach ($update in $updates) {
        $sizeInMB = if ($update.Size -and $update.Size -gt 0) { " ({0:N1} MB)" -f ($update.Size / 1MB) } else { "" }
        $title = if ($update.Title) { $update.Title } else { "Unknown Update" }
        Write-Host "  - $title$sizeInMB" -ForegroundColor Gray
    }

    # Log the updates separately to avoid duplication in transcript
    Write-Log "Found $($updates.Count) update(s) to install" -Level Info
    foreach ($update in $updates) {
        $sizeInMB = if ($update.Size -and $update.Size -gt 0) { " ({0:N1} MB)" -f ($update.Size / 1MB) } else { "" }
        $title = if ($update.Title) { $update.Title } else { "Unknown Update" }
        Write-Log "  - $title$sizeInMB" -Level Info
    }

    Write-Host ""
    Write-Host "Step 3: Installing updates (timeout: 15 minutes)..." -ForegroundColor Cyan
    Write-Log "Installing $($updates.Count) update(s) with 15-minute timeout..." -Level Info
    Write-Host "  - Note: Large updates may take several minutes each" -ForegroundColor Gray
    Write-Host ""

    # Create a runspace for timeout handling
    $timeoutMinutes = 15
    $timeoutSeconds = $timeoutMinutes * 60
    $startTime = Get-Date

    # Run updates in background job with timeout
    $updateJob = Start-Job -ScriptBlock {
        param($Updates)

        # Import PSWindowsUpdate module in the job context
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        $installedCount = 0
        $failedCount = 0
        $results = @()

        foreach ($update in $Updates) {
            $updateTitle = if ($update.Title) { $update.Title } else { "Unknown Update ($($update.KBArticleID))" }

            try {
                # Use Install-WindowsUpdate with the KB Article ID
                $result = Install-WindowsUpdate -KBArticleID $update.KBArticleID -AcceptAll -IgnoreReboot -ErrorAction Stop
                $results += [PSCustomObject]@{
                    Title = $updateTitle
                    Status = 'Success'
                    KB = $update.KBArticleID
                }
                $installedCount++
            } catch {
                $results += [PSCustomObject]@{
                    Title = $updateTitle
                    Status = 'Failed'
                    KB = $update.KBArticleID
                    Error = $_.Exception.Message
                }
                $failedCount++
            }
        }

        return @{
            Results = $results
            InstalledCount = $installedCount
            FailedCount = $failedCount
        }
    } -ArgumentList $updates

    # Monitor job with timeout
    $completed = $false
    $timedOut = $false
    $lastProgressUpdate = 0

    while (-not $completed) {
        $elapsed = (Get-Date) - $startTime
        $remainingSeconds = $timeoutSeconds - $elapsed.TotalSeconds

        if ($remainingSeconds -le 0) {
            $timedOut = $true
            break
        }

        # Check if job completed
        if ($updateJob.State -eq 'Completed') {
            $completed = $true
            break
        }

        # Show progress every 30 seconds (but not at 0 seconds)
        $currentSeconds = [math]::Floor($elapsed.TotalSeconds)
        if ($currentSeconds -gt 0 -and $currentSeconds % 30 -eq 0 -and $currentSeconds -ne $lastProgressUpdate) {
            $lastProgressUpdate = $currentSeconds
            $minutesElapsed = [math]::Floor($elapsed.TotalMinutes)
            $minutesRemaining = [math]::Ceiling($remainingSeconds / 60)
            Write-Host "  - Time elapsed: $minutesElapsed min | Remaining: $minutesRemaining min" -ForegroundColor DarkGray
        }

        Start-Sleep -Seconds 1
    }

    if ($timedOut) {
        # Timeout reached - notify user and continue
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "  UPDATE TIMEOUT REACHED" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Windows Updates are taking longer than $timeoutMinutes minutes." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Updates will continue in the background." -ForegroundColor White
        Write-Host "The deployment script will now proceed to the next step." -ForegroundColor White
        Write-Host ""
        Write-Host "You can:" -ForegroundColor Cyan
        Write-Host "  - Close this window safely" -ForegroundColor Gray
        Write-Host "  - Monitor updates manually using the links below" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Windows Update Settings:" -ForegroundColor White
        Write-Host "  - General updates: " -NoNewline -ForegroundColor Gray
        Write-Host "ms-settings:windowsupdate" -ForegroundColor Cyan
        Write-Host "  - Optional updates: " -NoNewline -ForegroundColor Gray
        Write-Host "ms-settings:windowsupdate-optionalupdates" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Opening Windows Update settings in 5 seconds..." -ForegroundColor Gray
        Write-Log "Windows Update timeout reached after $timeoutMinutes minutes - continuing with deployment" -Level Warning
        Write-Log "Updates are still running in the background" -Level Info

        # Open Windows Update settings
        Start-Sleep -Seconds 5
        try {
            Start-Process "ms-settings:windowsupdate"
        } catch {
            Write-Log "Failed to open Windows Update settings: $($_.Exception.Message)" -Level Warning
        }

        # Clean up job (leave it running)
        Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "Continuing with deployment..." -ForegroundColor Cyan
        Write-Host ""
        exit 0
    }

    # Job completed - get results
    $jobResult = Receive-Job -Job $updateJob
    Remove-Job -Job $updateJob -Force

    Write-Host ""
    Write-Host "Installation Results:" -ForegroundColor White

    foreach ($result in $jobResult.Results) {
        if ($result.Status -eq 'Success') {
            Write-Host "  [OK] " -NoNewline -ForegroundColor Green
            Write-Host "$($result.Title)" -ForegroundColor Gray
            Write-Log "  Installed: $($result.Title)" -Level Success
        } else {
            Write-Host "  [FAILED] " -NoNewline -ForegroundColor Red
            Write-Host "$($result.Title)" -ForegroundColor Gray
            Write-Log "  Failed: $($result.Title) - $($result.Error)" -Level Warning
        }
    }

    Write-Host ""
    Write-Log "Update summary: $($jobResult.InstalledCount) installed, $($jobResult.FailedCount) failed" -Level Info

    Write-Host ""
    if ($jobResult.FailedCount -eq 0) {
        Write-Host "Windows Update installation complete!" -ForegroundColor Green
        Write-Log "Windows Update installation complete - all updates successful." -Level Success
        $exitCode = 0
    } elseif ($jobResult.InstalledCount -gt 0) {
        Write-Host "Windows Update installation complete with errors!" -ForegroundColor Yellow
        Write-Log "Windows Update installation complete - some updates failed." -Level Warning
        $exitCode = 0  # Partial success
    } else {
        Write-Host "Windows Update installation failed!" -ForegroundColor Red
        Write-Log "Windows Update installation failed - no updates installed." -Level Error
        $exitCode = 1
    }

    Write-Host ""
    Write-Host "View update history: " -NoNewline -ForegroundColor Gray
    Write-Host "ms-settings:windowsupdate-history" -ForegroundColor Cyan

    exit $exitCode
} catch {
    Write-Host ""
    Write-Host "Windows Update installation failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log "Windows Update installation failed: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    # Prefer Complete-Script; if unavailable, stop transcript silently
    if (Get-Command Complete-Script -ErrorAction SilentlyContinue) {
        try { Complete-Script } catch { Stop-EmergencyTranscript }
    } else {
        Stop-EmergencyTranscript
    }
}
