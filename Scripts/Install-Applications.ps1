# WinDeploy Application Installer
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs applications via Windows Package Manager (WinGet).

.DESCRIPTION
    Automates application installation with architecture detection (x64/ARM64),
    intelligent exit code handling, and detailed logging. Integrates with Intune
    deployment tracking.

.EXAMPLE
    .\Install-Applications.ps1

.NOTES
    Requires : Admin rights (WinGet auto-installed if missing)
#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ============================================================================
# LOGGING PATTERN USED IN THIS SCRIPT
# ============================================================================
# This script uses a dual-output logging system for clarity:
#
# 1. Write-UserMessage: Screen-only output (banners, progress, UI elements)
#    - User sees clean, summarized progress
#    - NOT written to log files
#    - Example: "Installing Microsoft Office... DONE"
#
# 2. Write-Log: Detailed logging
#    - Goes to log file with full details
#    - Optionally shown on screen (use -NoConsole to hide)
#    - Can show different messages on screen vs log file using -ConsoleMessage
#    - Example: "Installing application: Microsoft.Office v16.0.12345 (Exit: 0)"
#
# Usage examples:
#   Write-UserMessage "Installing apps..." -Color Cyan          # Screen only
#   Write-Log "Detailed install info" -NoConsole                # Log only
#   Write-Log "Full details" -ConsoleMessage "Summary"          # Different messages
# ============================================================================

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Install-Applications.log' -RequiredModules @('Logging','System','Winget','Registry') -RequireAdmin

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Install-Application {
    <#
    .SYNOPSIS
        Installs a single application using WinGet.

    .DESCRIPTION
        Executes WinGet installation for specified application ID with proper
        error handling, exit code interpretation, and duration tracking.

    .PARAMETER AppId
        WinGet application ID to install.

    .PARAMETER WinGetPath
        Full path to winget.exe executable.

    .PARAMETER ForceInstall
        Force reinstall even if already installed.

    .OUTPUTS
        Hashtable with installation results including success status, exit code, and duration.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$WinGetPath,

        [switch]$ForceInstall
    )

    Write-Log "Installing: $AppId" -Level Info

    # Build WinGet arguments using helper
    $wingetArgs = New-WinGetInstallArgs -AppId $AppId -AdditionalArgs '--disable-interactivity'
    if ($ForceInstall) {
        $wingetArgs = New-WinGetInstallArgs -AppId $AppId -Force -AdditionalArgs '--disable-interactivity'
        Write-Log "  Force reinstall enabled" -Level Verbose
    }

    # Execute installation
    $startTime = Get-Date

    try {
        # Execute WinGet with output visible to transcript (no redirection)
        $process = Start-Process $WinGetPath -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

        $exitCode = $process.ExitCode
        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Get exit code description
        $exitDescription = Get-WinGetExitCodeDescription -ExitCode $exitCode

        # Check if installation succeeded
        # Exit codes that indicate success:
        #   0: Successfully installed
        #   -1978335189, -1978335135: Already installed
        #   -1978334967, -1978334966: Installed but needs reboot
        $isSuccess = $exitCode -in @(0, -1978335189, -1978335135, -1978334967, -1978334966)

        # Build result object
        $result = @{
            AppId = $AppId
            ExitCode = $exitCode
            Description = $exitDescription
            Duration = [math]::Round($duration, 1)
            Success = $isSuccess
        }

        # Log result
        if ($isSuccess) {
            Write-Log "  ✓ $exitDescription ($([math]::Round($duration, 1))s)" -Level Success
        } else {
            Write-Log "  ✗ $exitDescription (exit: $exitCode, $([math]::Round($duration, 1))s)" -Level Warning
        }

        return $result

    } catch {
        Write-Log "  ✗ Exception during installation: $($_.Exception.Message)" -Level Error

        return @{
            AppId = $AppId
            ExitCode = -1
            Description = "Exception: $($_.Exception.Message)"
            Duration = ((Get-Date) - $startTime).TotalSeconds
            Success = $false
        }
    }
}

function Test-AppInstalled {
    <#
    .SYNOPSIS
        Checks if an application is installed.

    .DESCRIPTION
        Checks for installed applications using two methods:
        1. UWP package check (Get-AppxPackage)
        2. WinGet list check

    .PARAMETER AppId
        WinGet application ID.

    .PARAMETER PackageNames
        UWP package names to check (supports wildcards).

    .PARAMETER WinGetPath
        Path to winget.exe for WinGet-based detection.

    .OUTPUTS
        [bool] True if app is installed, false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [string[]]$PackageNames,

        [string]$WinGetPath
    )

    # Check UWP packages first (faster)
    if ($PackageNames) {
        try {
            foreach ($packageName in $PackageNames) {
                # Check current user packages
                $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
                if (-not $package) {
                    # Check all users if not found for current user
                    $package = Get-AppxPackage -AllUsers -Name $packageName -ErrorAction SilentlyContinue
                }
                if ($package) {
                    return $true
                }
            }
        } catch {
            Write-Log "Unable to query package state for $AppId : $($_.Exception.Message)" -Level Verbose
        }
    }

    # Fall back to WinGet detection
    if ($WinGetPath) {
        try {
            $arguments = @('list', '--id', $AppId, '--exact', '--accept-source-agreements')
            $process = Start-Process -FilePath $WinGetPath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -eq 0) {
                return $true
            }
        } catch {
            Write-Log "WinGet detection for ${AppId} failed: $($_.Exception.Message)" -Level Verbose
        }
    }

    return $false
}

function Invoke-StoreFallback {
    <#
    .SYNOPSIS
        Opens Microsoft Store for manual installation and waits for completion.

    .DESCRIPTION
        When automated installation fails, this opens the Microsoft Store app page
        and polls for installation completion. Useful for apps that have Store-
        specific dependencies or requirements.

    .PARAMETER AppId
        WinGet application ID.

    .PARAMETER CurrentResult
        Installation result object to update.

    .PARAMETER WinGetPath
        Path to winget.exe for detection.

    .PARAMETER LaunchUri
        Microsoft Store URI (ms-windows-store://...).

    .PARAMETER ProductId
        Microsoft Store product ID.

    .PARAMETER DetectionPackageNames
        UWP package names to check during polling.

    .PARAMETER FriendlyName
        Human-readable app name.

    .PARAMETER WaitMinutes
        How long to wait for manual installation (default: 7 minutes).

    .PARAMETER CheckIntervalSeconds
        How often to check if app is installed (default: 15 seconds).

    .OUTPUTS
        Hashtable with updated installation result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [hashtable]$CurrentResult,

        [string]$WinGetPath,

        [string]$LaunchUri,

        [string]$ProductId,

        [string[]]$DetectionPackageNames,

        [string]$FriendlyName = $AppId,

        [int]$WaitMinutes = 7,

        [int]$CheckIntervalSeconds = 15
    )

    $fallbackStart = Get-Date

    # Check if already installed (app might have been installed since failure)
    if (Test-AppInstalled -AppId $AppId -PackageNames $DetectionPackageNames -WinGetPath $WinGetPath) {
        Write-Log "$FriendlyName already present; marking as installed" -Level Info
        $CurrentResult.Success = $true
        $CurrentResult.ExitCode = 0
        $CurrentResult.Description = 'Detected existing installation'
        $CurrentResult.Duration = [math]::Round(($CurrentResult.Duration + ((Get-Date) - $fallbackStart).TotalSeconds), 1)
        return $CurrentResult
    }

    # Open Microsoft Store to the app page
    if ($LaunchUri) {
        Write-Log "Opening Microsoft Store (timeout: ${WaitMinutes} minutes)" -Level Warning
        try {
            $null = Start-Process -FilePath 'explorer.exe' -ArgumentList $LaunchUri
        } catch {
            Write-Log "Unable to launch Microsoft Store: $($_.Exception.Message)" -Level Warning
        }
    }

    # Log what we're waiting for
    if ($ProductId) {
        Write-Log "Waiting for $FriendlyName (ProductId: $ProductId)..." -Level Info
    } else {
        Write-Log "Waiting for $FriendlyName..." -Level Info
    }

    # Poll for installation completion
    $deadline = $fallbackStart.AddMinutes($WaitMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $CheckIntervalSeconds
        if (Test-AppInstalled -AppId $AppId -PackageNames $DetectionPackageNames -WinGetPath $WinGetPath) {
            # App installed successfully
            $fallbackDuration = ((Get-Date) - $fallbackStart).TotalSeconds
            $CurrentResult.Success = $true
            $CurrentResult.ExitCode = 0
            $CurrentResult.Description = 'Installed via Microsoft Store'
            $CurrentResult.Duration = [math]::Round(($CurrentResult.Duration + $fallbackDuration), 1)
            Write-Log "  ✓ $FriendlyName installed ($([math]::Round($fallbackDuration, 1))s)" -Level Success
            return $CurrentResult
        }
    }

    # Timeout - app not detected
    Write-Log "$FriendlyName not detected within timeout window" -Level Warning
    $CurrentResult.Description = 'Manual installation required'
    return $CurrentResult
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

function Get-ApplicationDisplayName {
    <#
    .SYNOPSIS
        Resolves a human-friendly name for a winget application identifier.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$AppId)

    switch -Wildcard ($AppId) {
        'Microsoft.VCRedist.2015+.*' { return 'VC Redistributables' }
        'Microsoft.Office*' { return 'Microsoft 365 Apps' }
        'Microsoft.Teams*' { return 'Microsoft Teams' }
        'Microsoft.OneDrive*' { return 'OneDrive' }
        '7zip.7zip' { return '7-Zip' }
        'Microsoft.WindowsApp*' { return 'Windows App' }
        '9WZDNCRFJ3PZ' { return 'Company Portal' }
        default { return $AppId }
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {

    # [APPS] Ensure WinGet is available and functional
    Write-Log "[APPS] Checking WinGet availability..." -Level Info
    $wg = Initialize-WinGet
    $wingetPath = $wg.Path
    Write-Log "[APPS] WinGet ready (v$($wg.Version))" -Level Success

    # [APPS] Detect system architecture
    $isARM64 = $env:PROCESSOR_ARCHITECTURE -eq "ARM64"
    Write-Log "[APPS] System architecture: $env:PROCESSOR_ARCHITECTURE" -Level Info

    # [APPS] Install WinGet dependencies FIRST
    Write-Log "[APPS] Installing WinGet dependencies..." -Level Info
    Write-Log "[APPS]   - VC Libraries x64 Desktop" -Level Info
    Write-Log "[APPS]   - VC Libraries x86" -Level Info
    Write-Log "[APPS]   - UI.Xaml 2.8" -Level Info

    $dependencies = @(
        @{
            Id = 'Microsoft.VCLibs.140.00.UWPDesktop'
            DisplayName = 'VC Libraries x64 Desktop'
            AppxName = 'Microsoft.VCLibs.140.00.UWPDesktop'
        },
        @{
            Id = 'Microsoft.VCLibs.140.00'
            DisplayName = 'VC Libraries x86'
            AppxName = 'Microsoft.VCLibs.140.00'
        },
        @{
            Id = 'Microsoft.UI.Xaml.2.8'
            DisplayName = 'UI.Xaml 2.8'
            AppxName = 'Microsoft.UI.Xaml.2.8'
            FallbackSources = @('msstore')
            InstallerUri = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'
        }
    )

    # Install dependencies (result logged by Install-WinGetDependency)
    $dependencyResults = @($dependencies | Install-WinGetDependency -WinGetPath $wingetPath)
    if ($dependencyResults | Where-Object { -not $_.Satisfied }) {
        Write-Log "[APPS] Some dependencies failed to install" -Level Warning
    } else {
        Write-Log "[APPS] Dependencies installed successfully" -Level Success
    }

    # Store-backed apps that can fall back to manual Microsoft Store installs when winget fails
    $storeFallbacks = @{
        '9WZDNCRFJ3PZ' = @{
            FriendlyName = 'Company Portal'
            ProductId = '9WZDNCRFJ3PZ'
            LaunchUri = 'ms-windows-store://pdp/?ProductId=9WZDNCRFJ3PZ'
            PackageNames = @('Microsoft.CompanyPortal', 'Microsoft.CompanyPortal_8wekyb3d8bbwe')
            WebUrl = 'https://apps.microsoft.com/detail/9wzdncrfj3pz'
        }
        'Microsoft.Teams' = @{
            FriendlyName = 'Microsoft Teams'
            ProductId = 'XP8BT8DW290MPQ'
            LaunchUri = 'ms-windows-store://productid/XP8BT8DW290MPQ'
            PackageNames = @('MSTeams*', 'MicrosoftTeams*')
            WebUrl = 'https://apps.microsoft.com/detail/XP8BT8DW290MPQ'
        }
        'Microsoft.WindowsApp' = @{
            FriendlyName = 'Windows App'
            ProductId = '9N1F85V9T8BN'
            LaunchUri = 'ms-windows-store://productid/9N1F85V9T8BN'
            PackageNames = @('MicrosoftWindows.Client.WebExperience*', 'WindowsApp*')
            WebUrl = 'https://apps.microsoft.com/detail/9N1F85V9T8BN'
        }
    }

    # Default application set (no parameters accepted)
    $Applications = @(
        "Microsoft.VCRedist.2015+.x64",      # Install VCRedist first (common dependency)
        "Microsoft.Office",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip",
        "Microsoft.WindowsApp",
        "9WZDNCRFJ3PZ"                       # Company Portal (Store ID, dependencies installed above)
    )

    # Replace x64 packages with ARM64 equivalents if needed
    if ($isARM64) {
        Write-Log "[APPS] ARM64 detected - adjusting package names" -Level Info
        $Applications = $Applications | ForEach-Object {
            # Replace .x64 with .arm64 in package IDs
            if ($_ -match '\.x64(\.|$)') {
                $_ -replace '\.x64(\.|$)', '.arm64$1'
            } else {
                $_
            }
        }
        Write-Log "[APPS] Adjusted applications: $($Applications -join ', ')" -Level Info
    }

    # [APPS] Install applications
    Write-UserMessage ""
    Write-UserMessage "========================================" -Color Cyan
    Write-UserMessage "  APPLICATION INSTALLATION" -Color Cyan
    Write-UserMessage "========================================" -Color Cyan
    Write-UserMessage ""

    Write-Log "Starting installation of $($Applications.Count) applications..." -ConsoleMessage "Applications to install:" -Level Info

    foreach ($app in $Applications) {
        $displayName = Get-ApplicationDisplayName -AppId $app
        Write-UserMessage "  - $displayName" -Color Gray
        Write-Log "Application queued: $app ($displayName)" -NoConsole
    }
    Write-UserMessage ""

    $results = @()
    $currentApp = 0
    foreach ($app in $Applications) {
        $currentApp++
        $appDisplayName = Get-ApplicationDisplayName -AppId $app

        # Screen: Show clean progress with app name
        Write-UserMessage "[$currentApp/$($Applications.Count)] $appDisplayName" -Color Cyan

        # Log: Record detailed start information
        Write-Log "[$currentApp/$($Applications.Count)] Starting installation: $app ($appDisplayName)" -NoConsole
        # Attempt installation
        $result = Install-Application -AppId $app -WinGetPath $wingetPath

        # If installation failed, try recovery methods
        if (-not $result.Success) {
            # Check for missing dependency error
            if ($result.ExitCode -eq -1978334972) {
                Write-Log "  Missing dependency, attempting repair..." -Level Warning

                try {
                    # Try repairing WinGet if module is available
                    if (Get-Module -Name Microsoft.WinGet.Client -ListAvailable) {
                        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
                        Write-Log "  Repairing WinGet..." -Level Info
                        Repair-WinGetPackageManager -Force -Latest -Verbose | Out-Null

                        # Retry installation after repair
                        Start-Sleep -Seconds 3
                        $retryResult = Install-Application -AppId $app -WinGetPath $wingetPath
                        if ($retryResult.Success) {
                            Write-Log "  ✓ Installed after repair" -Level Success
                            $result = $retryResult
                        }
                    }
                } catch {
                    Write-Log "  Repair failed: $($_.Exception.Message)" -Level Warning
                }

                # Try Microsoft Store source as fallback
                if (-not $result.Success) {
                    Write-Log "  Trying Microsoft Store source..." -Level Warning
                    $wingetArgs = @('install', '--id', $app, '--source', 'msstore', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--force')
                    $process = Start-Process $wingetPath -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                    $exitCode = $process.ExitCode
                    $isSuccess = $exitCode -in @(0, -1978335189, -1978335135, -1978334967, -1978334966)

                    if ($isSuccess) {
                        Write-Log "  ✓ Installed from Microsoft Store" -Level Success
                        $result.Success = $true
                        $result.ExitCode = $exitCode
                        $result.Description = "Installed from msstore"
                    }
                }
            }
        }

        $results += $result

        # Screen: Show simple completion status
        if ($result.Success) {
            Write-UserMessage "  ✓ Completed in $($result.Duration)s" -Color Green
        } else {
            Write-UserMessage "  ✗ Failed: $($result.Description)" -Color Red
        }
        Write-UserMessage ""

        # Log: Record detailed result
        if ($result.Success) {
            Write-Log "Installation successful: $app completed in $($result.Duration)s (Exit: $($result.ExitCode))" -NoConsole -Level Success
        } else {
            Write-Log "Installation failed: $app - Exit code: $($result.ExitCode), Description: $($result.Description), Duration: $($result.Duration)s" -NoConsole -Level Warning
        }

        if (-not $result.Success -and $storeFallbacks.ContainsKey($app)) {
            $storeInfo = $storeFallbacks[$app]

            # Give the user an interactive Store fallback and poll for completion
            $result = Invoke-StoreFallback -AppId $app -CurrentResult $result -WinGetPath $wingetPath -LaunchUri $storeInfo.LaunchUri -ProductId $storeInfo.ProductId -DetectionPackageNames $storeInfo.PackageNames -FriendlyName $storeInfo.FriendlyName

            if (-not $result.Success) {
                Write-Log "" -Level Info
                Write-Log "  ⚠ $($storeInfo.FriendlyName) installation requires manual action." -Level Warning
                if ($storeInfo.LaunchUri) {
                    Write-Log "  → Launch Store: $($storeInfo.LaunchUri)" -Level Info
                }
                if ($storeInfo.WebUrl) {
                    Write-Log "  → Web link: $($storeInfo.WebUrl)" -Level Info
                }
                Write-Log "  → Or run: winget install $app --source msstore" -Level Info
                Write-Log "" -Level Info

                # Mark as skipped rather than failed for reporting purposes
                $result.Description = 'Manual installation required'
            }
        }
    }

    $installedResults = @($results | Where-Object { $_.Success })
    $failedOrSkippedResults = @($results | Where-Object { -not $_.Success })

    # Screen: Clean summary display - only show sections with content
    if ($installedResults.Count -gt 0) {
        Write-UserMessage "Successfully installed:" -Color Green
        foreach ($result in $installedResults) {
            $displayName = Get-ApplicationDisplayName -AppId $result.AppId
            Write-UserMessage "  - $displayName" -Color Green
        }
        Write-UserMessage ""
    }

    if ($failedOrSkippedResults.Count -gt 0) {
        Write-UserMessage "Failed/skipped:" -Color Yellow
        foreach ($result in $failedOrSkippedResults) {
            $displayName = Get-ApplicationDisplayName -AppId $result.AppId
            $note = if ($result.Description) { " ($($result.Description))" } else { '' }
            Write-UserMessage "  - $displayName$note" -Color Yellow
        }
        Write-UserMessage ""
    }

    # Log: Detailed summary with all metadata
    Write-Log "Installation summary - Successfully installed:" -NoConsole
    if ($installedResults.Count -gt 0) {
        foreach ($result in $installedResults) {
            Write-Log "  - $($result.AppId) (Exit: $($result.ExitCode), Duration: $($result.Duration)s)" -NoConsole -Level Success
        }
    } else {
        Write-Log "  - None" -NoConsole
    }

    Write-Log "Installation summary - Failed/skipped:" -NoConsole
    if ($failedOrSkippedResults.Count -gt 0) {
        foreach ($result in $failedOrSkippedResults) {
            Write-Log "  - $($result.AppId) - Exit: $($result.ExitCode), Reason: $($result.Description), Duration: $($result.Duration)s" -NoConsole -Level Warning
        }
    } else {
        Write-Log "  - None" -NoConsole
    }

    # Generate summary
    $successResults = @($results | Where-Object { $_.Success })
    $failedResults = @($results | Where-Object { -not $_.Success })
    $skippedResults = @($failedResults | Where-Object { $_.Description -match '(?i)manual installation required' })
    $criticalFailures = @($failedResults | Where-Object { $_.Description -notmatch '(?i)manual installation required' })

    $successCount = $successResults.Count
    $failedCount = $criticalFailures.Count
    $skippedCount = $skippedResults.Count
    $totalDuration = ($results | Measure-Object -Property Duration -Sum).Sum

    Write-Log "" -Level Info
    Write-Log "======================================" -Level Info
    Write-Log "Installation Summary:" -Level Info
    Write-Log "  Total applications: $($Applications.Count)" -Level Info
    Write-Log "  Successfully installed: $successCount" -Level $(if ($successCount -gt 0) { 'Success' } else { 'Info' })
    if ($skippedCount -gt 0) {
        Write-Log "  Skipped (manual install needed): $skippedCount" -Level Info
    }
    Write-Log "  Failed: $failedCount" -Level $(if ($failedCount -gt 0) { 'Warning' } else { 'Info' })
    Write-Log "  Total duration: $([math]::Round($totalDuration, 1))s" -Level Info
    Write-Log "======================================" -Level Info

    # Set Intune success marker if all critical installations succeeded (skipped items don't count as failures)
    if ($failedCount -eq 0) {
        Set-IntuneSuccess -AppName 'ApplicationBundle' -Version (Get-Date -Format 'yyyy.MM.dd')
        if ($skippedCount -gt 0) {
            Write-Log "All critical applications installed successfully ($skippedCount skipped)" -Level Success
        } else {
            Write-Log "All applications installed successfully" -Level Success
        }
    } else {
        Write-Log "Some applications failed to install" -Level Warning
    }

    # Exit with error only if there are critical failures (not just skipped items)
    exit $(if ($failedCount -gt 0) { 1 } else { 0 })

} catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    if ($_.ScriptStackTrace) {
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    }
    exit 1
} finally {
    Complete-DeploymentScript
}
