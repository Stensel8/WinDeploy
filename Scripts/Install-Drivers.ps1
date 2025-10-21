<#PSScriptInfo

.AUTHOR Sten Tijhuis

.COMPANYNAME WinDeploy

.TAGS PowerShell Windows Drivers Dell HP DCU HPIA Deployment

.PROJECTURI https://github.com/Stensel8/WinDeploy

#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs vendor-specific driver update tools and updates drivers.

.DESCRIPTION
    Automatically detects system manufacturer (Dell or HP) and installs/runs
    the appropriate driver update tool with vendor-specific optimizations.

    Supported Vendors:
    - Dell: Dell Command Update (DCU)
    - HP: HP Image Assistant (HPIA)

    Features:
    - Automatic manufacturer detection
    - Vendor-specific driver tool installation
    - Automated driver updates
    - Detailed logging and error handling
    - Integration with Intune deployment tracking

.EXAMPLE
    .\Install-Drivers.ps1
    Automatically detects manufacturer and updates drivers.

.NOTES
    Version      : See VERSION file in repository root
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Requires     : Admin rights, WinGet (for Dell), Internet connection

.LINK
    Project Site: https://github.com/Stensel8/WinDeploy
#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Handle remote execution where $PSScriptRoot is empty (e.g., when script is invoked via iex/Invoke-Expression)
# Without this fallback, the script cannot locate required dependency files like device list JSONs
$script:ScriptRoot = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    # When running via iex, try to find the script location from common paths
    $possiblePaths = @(
        'C:\WinDeploy\Download',
        (Get-Location).Path
    )
    $foundPath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($foundPath) { $foundPath } else { $PWD.Path }
}

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $script:ScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Install-Drivers.log' -RequiredModules @('Logging','System','Registry','Winget') -RequireAdmin -CallerScriptRoot $script:ScriptRoot

try {
    Write-Log "[DRIVERS] Starting driver update process..." -Level Info

    # Get system manufacturer and model
    Write-Log "[DRIVERS] Detecting system manufacturer and model..." -Level Verbose
    try {
        $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = $systemInfo.Manufacturer.ToLower()
        $model = $systemInfo.Model
        Write-Log "[DRIVERS] System: $manufacturer $model" -Level Info
    } catch {
        Write-Log "[DRIVERS] Unable to detect system manufacturer: $($_.Exception.Message)" -Level Error
        exit 1
    }

    # Load lists of supported devices
    Write-Log "[DRIVERS] Loading supported device lists..." -Level Verbose
    $supportedDellDevices = @()
    $supportedHPDevices = @()

    # Try multiple locations for device list JSON files
    $dellListCandidates = @(
        (Join-Path $script:ScriptRoot "..\Docs\SupportedDellDevices.json"),
        "C:\WinDeploy\Download\Docs\SupportedDellDevices.json",
        "C:\WinDeploy\Docs\SupportedDellDevices.json"
    )
    $hpListCandidates = @(
        (Join-Path $script:ScriptRoot "..\Docs\SupportedHPDevices.json"),
        "C:\WinDeploy\Download\Docs\SupportedHPDevices.json",
        "C:\WinDeploy\Docs\SupportedHPDevices.json"
    )

    $dellListPath = $dellListCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $hpListPath = $hpListCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    # Load Dell device list
    if (Test-Path $dellListPath) {
        try {
            $supportedDellDevices = Get-Content $dellListPath -Raw | ConvertFrom-Json
            Write-Log "[DRIVERS] Loaded $($supportedDellDevices.Count) Dell device patterns" -Level Verbose
        } catch {
            Write-Log "[DRIVERS] Unable to load Dell device list: $($_.Exception.Message)" -Level Warning
        }
    }

    # Load HP device list
    if (Test-Path $hpListPath) {
        try {
            $supportedHPDevices = Get-Content $hpListPath -Raw | ConvertFrom-Json
            Write-Log "[DRIVERS] Loaded $($supportedHPDevices.Count) HP device patterns" -Level Verbose
        } catch {
            Write-Log "[DRIVERS] Unable to load HP device list: $($_.Exception.Message)" -Level Warning
        }
    }

    # Check if this device is supported for driver updates
    Write-Log "[DRIVERS] Checking device compatibility..." -Level Verbose
    $isSupported = $false
    $matchedPattern = $null

    # Check Dell devices
    if ($manufacturer -like "*dell*") {
        foreach ($pattern in $supportedDellDevices) {
            if ($model -like "*$pattern*") {
                $isSupported = $true
                $matchedPattern = $pattern
                break
            }
        }
        if ($isSupported) {
            Write-Log "[DRIVERS] Dell device supported (pattern: '$matchedPattern')" -Level Verbose
        } else {
            Write-Log "[DRIVERS] Dell device not supported (model: '$model')" -Level Info
        }
    }
    # Check HP devices
    elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        foreach ($pattern in $supportedHPDevices) {
            if ($model -like "*$pattern*") {
                $isSupported = $true
                $matchedPattern = $pattern
                break
            }
        }
        if ($isSupported) {
            Write-Log "[DRIVERS] HP device supported (pattern: '$matchedPattern')" -Level Verbose
        } else {
            Write-Log "[DRIVERS] HP device not supported (model: '$model')" -Level Info
        }
    }

    # Exit if device not supported
    if (-not $isSupported) {
        Write-Host "Skipped: Unsupported device" -ForegroundColor Yellow
        Write-Log "[DRIVERS] Device '$model' not in supported list" -Level Warning
        Write-Log "[DRIVERS] Driver installation skipped" -Level Warning
        exit 2
    }

    # Check if WinGet is available (needed for installing vendor tools)
    Write-Log "[DRIVERS] Checking WinGet availability..." -Level Verbose
    $winget = $null
    try {
        $winget = Test-WinGetFunctional
    } catch {
        Write-Log "[DRIVERS] WinGet not functional: $($_.Exception.Message)" -Level Warning
    }
    $wingetPath = if ($winget) { $winget.Path } else { 'winget' }
    Write-Log "[DRIVERS] WinGet path: $wingetPath" -Level Verbose

    # Dell drivers
    if ($manufacturer -like "*dell*") {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  DELL DRIVER UPDATE PROCESS" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Device: " -NoNewline -ForegroundColor Gray
        Write-Host "$model" -ForegroundColor White
        Write-Host "  Pattern matched: " -NoNewline -ForegroundColor Gray
        Write-Host "'$matchedPattern'" -ForegroundColor Green
        Write-Host ""

        Write-Host "Step 1: Installing Dell Command Update..." -ForegroundColor Cyan
        Write-Log "[DRIVERS] Installing Dell Command Update..." -Level Info
        Write-Host "  - Downloading Dell Command Update from WinGet..." -ForegroundColor Gray
        Write-Log "[DRIVERS]   - Downloading Dell Command Update" -Level Verbose

        $installArgs = New-WinGetInstallArgs -AppId "Dell.CommandUpdate"
        $result = Start-Process $wingetPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        $exitCode = $result.ExitCode
        $exitDesc = Get-WinGetExitCodeDescription -ExitCode $exitCode

        Write-Host "  - Installing DCU CLI tool..." -ForegroundColor Gray
        Write-Log "[DRIVERS]   - Installing DCU CLI tool" -Level Verbose

        if ($exitCode -in @(0, -1978335189, -1978335135)) {
            Write-Host "  - Dell Command Update: READY" -ForegroundColor Green
            Write-Log "[DRIVERS] Dell Command Update ready: $exitDesc" -Level Info

            # Find Dell Command Update executable
            Write-Host ""
            Write-Host "Step 2: Locating Dell Command Update..." -ForegroundColor Cyan
            Write-Log "[DRIVERS] Locating Dell Command Update..." -Level Verbose
            $dcuPaths = @(
                "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
                "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
            )

            $dcu = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

            if ($dcu) {
                Write-Host "  - Found DCU at: $dcu" -ForegroundColor White
                Write-Host ""
                Write-Host "Step 3: Scanning for driver updates..." -ForegroundColor Cyan
                Write-Log "[DRIVERS] Scanning for driver updates..." -Level Verbose
                Write-Host "  - Running Dell Command Update scan..." -ForegroundColor Gray

                # Scan for available updates
                $scanResult = Start-Process $dcu -ArgumentList "/scan", "-silent" -Wait -PassThru -NoNewWindow

                # Process scan results
                if ($scanResult.ExitCode -eq 0) {
                    Write-Host "  - Scan: COMPLETE" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Step 4: Installing driver updates..." -ForegroundColor Cyan
                    Write-Log "[DRIVERS] Applying driver updates..." -Level Verbose
                    Write-Host "  - Downloading and installing drivers..." -ForegroundColor Gray

                    # Apply driver updates (disable reboot to prevent interruption)
                    $applyResult = Start-Process $dcu -ArgumentList "/applyUpdates", "-reboot=disable", "-silent" -Wait -PassThru -NoNewWindow

                    # Handle different exit codes
                    switch ($applyResult.ExitCode) {
                        0 {
                            # Success
                            Write-Host ""
                            Write-Host "  - Installation: COMPLETE" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "Dell driver updates completed" -ForegroundColor Green
                            Write-Log "[DRIVERS] Dell updates completed" -Level Info
                        }
                        1 {
                            # Success but reboot needed
                            Write-Host ""
                            Write-Host "  - Installation: COMPLETE (reboot recommended)" -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Dell driver updates completed (reboot recommended)" -ForegroundColor Green
                            Write-Log "[DRIVERS] Dell updates completed - reboot recommended" -Level Info
                        }
                        500 {
                            # No updates available
                            Write-Host ""
                            Write-Host "  - Installation: NOT NEEDED" -ForegroundColor Cyan
                            Write-Host ""
                            Write-Host "Dell system is up to date" -ForegroundColor Green
                            Write-Log "[DRIVERS] Dell system is up to date" -Level Info
                        }
                        default {
                            # Error occurred
                            Write-Host ""
                            Write-Host "  - Installation: FAILED" -ForegroundColor Red
                            Write-Host ""
                            Write-Host "Dell driver updates failed (exit code: $($applyResult.ExitCode))" -ForegroundColor Yellow
                            Write-Log "[DRIVERS] Dell updates failed (exit: $($applyResult.ExitCode))" -Level Warning
                        }
                    }
                } elseif ($scanResult.ExitCode -eq 500) {
                    # No updates found during scan
                    Write-Host ""
                    Write-Host "  - Scan: NO UPDATES AVAILABLE" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Dell system is up to date" -ForegroundColor Green
                    Write-Log "[DRIVERS] Dell system is up to date" -Level Info
                } else {
                    # Scan failed
                    Write-Host ""
                    Write-Host "  - Scan: FAILED" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Dell driver scan failed (exit code: $($scanResult.ExitCode))" -ForegroundColor Yellow
                    Write-Log "[DRIVERS] Scan failed (exit: $($scanResult.ExitCode))" -Level Warning
                }
            } else {
                Write-Log "[DRIVERS] DCU executable not found" -Level Error
                Write-Log "[DRIVERS] Driver update process failed" -Level Error
                exit 1
            }
        } else {
            Write-Log "[DRIVERS] Dell Command Update installation failed: $exitDesc" -Level Error
            Write-Log "[DRIVERS] Driver update process failed" -Level Error
            exit 1
        }
    }
    # HP drivers
    elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  HP DRIVER UPDATE PROCESS" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Device: " -NoNewline -ForegroundColor Gray
        Write-Host "$model" -ForegroundColor White
        Write-Host "  Pattern matched: " -NoNewline -ForegroundColor Gray
        Write-Host "'$matchedPattern'" -ForegroundColor Green
        Write-Host ""

        # Check if HP Image Assistant is already installed
        Write-Host "Step 1: Checking for HP Image Assistant..." -ForegroundColor Cyan
        Write-Log "[DRIVERS] Checking for HP Image Assistant..." -Level Verbose
        $hpiaPaths = @(
            "C:\Program Files\HP\HPIA\HPImageAssistant.exe",
            "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe"
        )

        $hpia = $hpiaPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $hpia) {
            # Not found, install it
            Write-Host "  - HP Image Assistant: NOT FOUND" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Step 2: Installing HP Image Assistant..." -ForegroundColor Cyan
            Write-Log "[DRIVERS] Installing HP Image Assistant..." -Level Info
            Write-Host "  - Downloading HP Image Assistant..." -ForegroundColor Gray
            Write-Host "  - Installing HPIA..." -ForegroundColor Gray

            $installArgs = New-WinGetInstallArgs -AppId "HP.ImageAssistant"
            $result = Start-Process $wingetPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
            $exitCode = $result.ExitCode
            $exitDesc = Get-WinGetExitCodeDescription -ExitCode $exitCode

            if ($exitCode -in @(0, -1978335189, -1978335135)) {
                Write-Log "[DRIVERS] HP Image Assistant ready: $exitDesc" -Level Info
            } else {
                Write-Log "[DRIVERS] HP Image Assistant installation failed: $exitDesc" -Level Warning
            }
            Write-Log "[DRIVERS] Verifying installation..." -Level Verbose
            # Verify installation
            $hpia = $hpiaPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        } else {
            Write-Host "  - HP Image Assistant: ALREADY INSTALLED" -ForegroundColor Green
            Write-Log "[DRIVERS] HP Image Assistant already installed" -Level Info
        }

        if ($hpia) {
            Write-Host ""
            Write-Host "Step 3: Running HP Image Assistant..." -ForegroundColor Cyan
            Write-Host "  - Found HPIA at: $hpia" -ForegroundColor White
            Write-Log "[DRIVERS] Running HP Image Assistant..." -Level Info
            Write-Host "  - Analyzing system for driver updates..." -ForegroundColor Gray
            Write-Host "  - Installing available drivers (this may take a while)..." -ForegroundColor Gray

            # Create temporary folder for HPIA reports
            $workPath = Join-Path $env:TEMP "HPIA"
            New-Item -ItemType Directory -Path $workPath -Force | Out-Null

            # Run HPIA to analyze and install drivers
            $hpiaArgs = @(
                "/Operation:Analyze",
                "/Category:All",
                "/Selection:All",
                "/InstallType:All",
                "/Action:Install",
                "/Silent",
                "/ReportFolder:$workPath"
            )

            $hpiaResult = Start-Process $hpia -ArgumentList $hpiaArgs -Wait -PassThru -NoNewWindow

            # Check if a report was generated (indicates success)
            $report = Get-ChildItem -Path $workPath -Filter *.html -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($report) {
                # Report found - HPIA completed successfully
                Write-Host ""
                Write-Host "  - Analysis & Installation: COMPLETE" -ForegroundColor Green
                Write-Host ""
                Write-Host "HP Image Assistant completed" -ForegroundColor Green
                Write-Host "  - Report generated: $($report.FullName)" -ForegroundColor White
                Write-Log "[DRIVERS] HP Image Assistant completed - report generated" -Level Info
                Write-Log "[DRIVERS] Report: $($report.FullName)" -Level Verbose

                if ($hpiaResult.ExitCode -ne 0) {
                    Write-Host "  - Note: Exit code $($hpiaResult.ExitCode) may indicate warnings" -ForegroundColor Yellow
                    Write-Log "[DRIVERS] Exit code $($hpiaResult.ExitCode) may indicate warnings" -Level Warning
                }
            } else {
                # No report - check exit code
                switch ($hpiaResult.ExitCode) {
                    0 {
                        # Success
                        Write-Host ""
                        Write-Host "  - Analysis & Installation: COMPLETE" -ForegroundColor Green
                        Write-Host ""
                        Write-Host "HP Image Assistant completed" -ForegroundColor Green
                        Write-Log "[DRIVERS] HP Image Assistant completed" -Level Success
                    }
                    4097 {
                        # Warnings (often unsupported OS version)
                        Write-Host ""
                        Write-Host "  - Analysis & Installation: COMPLETE (warnings)" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "HP system may be up to date or OS version not fully supported" -ForegroundColor Cyan
                        Write-Log "[DRIVERS] HP system may be up to date or OS version not fully supported" -Level Info
                    }
                    default {
                        # Error
                        Write-Host ""
                        Write-Host "  - Analysis & Installation: FAILED" -ForegroundColor Red
                        Write-Host ""
                        Write-Host "HP Image Assistant failed (exit code: $($hpiaResult.ExitCode))" -ForegroundColor Yellow
                        Write-Log "[DRIVERS] HP Image Assistant failed (exit: $($hpiaResult.ExitCode))" -Level Warning
                    }
                }
            }

            # Clean up temporary files
            Remove-Item -Path $workPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "[DRIVERS] HP Image Assistant not found" -Level Error
            Write-Log "[DRIVERS] Driver update process failed" -Level Error
            exit 1
        }
    }
    else {
        Write-Log "[DRIVERS] Manufacturer '$manufacturer' is not supported for automatic driver installation." -Level Warning
        Write-Log "[DRIVERS] Supported manufacturers: Dell, HP" -Level Info
    }

    Write-Log "[DRIVERS] Driver update process completed" -Level Success
    exit 0

} catch {
    Write-Log "Driver update failed: $_" -Level Error
    exit 1
} finally {
    Complete-DeploymentScript
}
