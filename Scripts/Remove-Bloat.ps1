# WinDeploy Bloatware Removal Utility
# Part of the WinDeploy Automation Toolkit
# See RELEASES.md for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes bloatware applications and prevents their automatic reinstallation.

.DESCRIPTION
    This script removes unwanted Windows applications (bloatware) from the system.
    It removes both installed packages (for current users) and provisioned packages
    (preventing installation for new users). Additionally, it configures registry
    settings to prevent Windows from automatically reinstalling bloatware.

.EXAMPLE
    .\Remove-Bloat.ps1

.NOTES
    Created by   : Sten Tijhuis
    Project      : WinDeploy
    Requires     : Admin rights
    Version      : See VERSION file in repository root

.LINK
    Project Site: https://github.com/Stensel8/WinDeploy
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Remove-Bloat.log' -RequiredModules @('Logging','System','Registry') -RequireAdmin

# Remove Appx module if already loaded to prevent assembly conflicts
try {
    if (Get-Module -Name Appx) {
        Remove-Module -Name Appx -Force -ErrorAction SilentlyContinue
    }
} catch {
    # Silently continue if module removal fails (module may not be loaded)
    Write-Verbose "Appx module removal skipped: $($_.Exception.Message)"
}

# List of unwanted apps to remove
$AppsToRemove = @(
    # Microsoft Apps - Communication and Social
    "Microsoft.SkypeApp",
    "Microsoft.YourPhone",
    "Microsoft.People",
    "Microsoft.Messaging",

    # Media and Entertainment
    "Microsoft.GamingApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.Media.Player",

    # Productivity and Tools
    "Microsoft.Todos",
    "Microsoft.WindowsMaps",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.OneConnect",
    # "Microsoft.GetHelp",  # Excluded: Required for Windows troubleshooting/support (Issue #59)
    "Microsoft.Getstarted",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.3DBuilder",
    "Microsoft.Print3D",
    "Microsoft.MixedReality.Portal",
    "Microsoft.Clipchamp",
    "Clipchamp.Clipchamp",
    "9P1J8S7CCWWT",
    "MicrosoftCorporationII.MicrosoftFamily",
    "Microsoft.WindowsAlarms",
    "Microsoft.ScreenSketch",
    "Microsoft.Wallet",
    "Microsoft.NetworkSpeedTest",
    "Microsoft.MicrosoftJournal",
    "Microsoft.MicrosoftPowerBIForWindows",
    "Microsoft.Office.Sway",

    # News, Weather, and Information
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.BingFinance",
    "Microsoft.BingFoodAndDrink",
    "Microsoft.BingHealthAndFitness",
    "Microsoft.BingSports",
    "Microsoft.BingTranslator",
    "Microsoft.BingTravel",
    "Microsoft.News",
    "Microsoft.Start",
    "Microsoft.BingSearch",
    "Microsoft.WebExperiencePack",

    # AI and Assistant
    "Microsoft.Copilot",
    "Microsoft.549981C3F5F10",

    # System & Utility
    "Microsoft.PowerAutomateDesktop",

    # Third Party Apps - Social Media
    "Facebook",
    "Instagram",
    "Twitter",
    "TikTok",
    "LinkedInforWindows",
    "XING",

    # Entertainment and Streaming
    "SpotifyAB.SpotifyMusic",
    "Spotify",
    "Netflix",
    "AmazonVideo.PrimeVideo",
    "Amazon.com.Amazon",
    "HULULLC.HULUPLUS",
    "Plex",
    "Disney",
    "DisneyMagicKingdoms",
    "SlingTV",
    "PandoraMediaInc",
    "iHeartRadio",
    "TuneInRadio",
    "Shazam",

    # Games
    "king.com.CandyCrushSaga",
    "king.com.CandyCrushSodaSaga",
    "king.com.BubbleWitch3Saga",
    "CaesarsSlotsFreeCasino",
    "COOKINGFEVER",
    "FarmVille2CountryEscape",
    "MarchofEmpires",
    "Royal Revolt",
    "Asphalt8Airborne",
    "HiddenCity",

    # Productivity and Utilities
    "Duolingo-LearnLanguagesforFree",
    "NYTCrossword",
    "Flipboard",
    "OneCalendar",
    "Wunderlist",
    "fitbit",
    "Viber",
    "WinZipUniversal",
    "EclipseManager",
    "Sidia.LiveWallpaper",

    # Creative and Photo Editing
    "AdobeSystemsIncorporated.AdobePhotoshopExpress",
    "AutodeskSketchBook",
    "DrawboardPDF",
    "PhototasticCollage",
    "PicsArt-PhotoStudio",
    "PolarrPhotoEditorAcademicEdition",
    "ActiproSoftwareLLC",
    "ACGMediaPlayer",
    "CyberLinkMediaSuiteEssentials"
)

# Cache for packages to avoid redundant queries
$script:InstalledPackagesCache = $null
$script:ProvisionedPackagesCache = $null

function Get-CachedInstalledPackage {
    <#
    .SYNOPSIS
        Retrieves cached list of installed AppX packages.
    .DESCRIPTION
        Returns cached AppX package list to avoid repeated WMI queries.
        Uses Windows PowerShell for PS7+ compatibility.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    # Only query once - cache the results
    if ($null -eq $script:InstalledPackagesCache) {
        Write-Log "Caching all installed packages for faster pattern matching..." -Level Info

        # PS7 can't use Appx module directly due to assembly conflicts
        # So we shell out to Windows PowerShell 5.1
        $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

        if ($useWindowsPowerShell) {
            try {
                # Build command to run in Windows PowerShell
                $scriptBlock = @"
Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | ConvertTo-Json -Compress
"@
                # Execute in powershell.exe (Windows PowerShell 5.1)
                $result = powershell.exe -NoProfile -Command $scriptBlock
                if ($result -and $result -ne "null") {
                    $script:InstalledPackagesCache = $result | ConvertFrom-Json
                    # Ensure we have an array (single results come back as object)
                    if ($script:InstalledPackagesCache -isnot [array]) {
                        $script:InstalledPackagesCache = @($script:InstalledPackagesCache)
                    }
                } else {
                    $script:InstalledPackagesCache = @()
                }
            } catch {
                Write-Log "Error caching installed packages: $($_.Exception.Message)" -Level Warning
                $script:InstalledPackagesCache = @()
            }
        } else {
            # Running in Windows PowerShell - use module directly
            try {
                $script:InstalledPackagesCache = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object Name, PackageFullName)
            } catch {
                Write-Log "Error caching installed packages: $($_.Exception.Message)" -Level Warning
                $script:InstalledPackagesCache = @()
            }
        }
        Write-Log "Cached $($script:InstalledPackagesCache.Count) installed packages" -Level Info
    }
    return $script:InstalledPackagesCache
}

function Get-CachedProvisionedPackage {
    <#
    .SYNOPSIS
        Retrieves cached list of provisioned AppX packages.
    .DESCRIPTION
        Returns cached provisioned package list to avoid repeated WMI queries.
        Provisioned packages = packages that get installed for NEW users.
        Uses Windows PowerShell for PS7+ compatibility.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    # Only query once - cache the results
    if ($null -eq $script:ProvisionedPackagesCache) {
        Write-Log "Caching all provisioned packages for faster pattern matching..." -Level Info

        # PS7 can't use Appx module directly due to assembly conflicts
        $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

        if ($useWindowsPowerShell) {
            try {
                # Build command to run in Windows PowerShell
                $scriptBlock = @"
Get-AppxProvisionedPackage -Online | Select-Object PackageName, DisplayName | ConvertTo-Json -Compress
"@
                # Execute in powershell.exe (Windows PowerShell 5.1)
                $result = powershell.exe -NoProfile -Command $scriptBlock
                if ($result -and $result -ne "null") {
                    $script:ProvisionedPackagesCache = $result | ConvertFrom-Json
                    # Ensure array
                    if ($script:ProvisionedPackagesCache -isnot [array]) {
                        $script:ProvisionedPackagesCache = @($script:ProvisionedPackagesCache)
                    }
                } else {
                    $script:ProvisionedPackagesCache = @()
                }
            } catch {
                Write-Log "Error caching provisioned packages: $($_.Exception.Message)" -Level Warning
                $script:ProvisionedPackagesCache = @()
            }
        } else {
            # Running in Windows PowerShell - use module directly
            try {
                $script:ProvisionedPackagesCache = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object PackageName, DisplayName)
            } catch {
                Write-Log "Error caching provisioned packages: $($_.Exception.Message)" -Level Warning
                $script:ProvisionedPackagesCache = @()
            }
        }
        Write-Log "Cached $($script:ProvisionedPackagesCache.Count) provisioned packages" -Level Info
    }
    return $script:ProvisionedPackagesCache
}

function Remove-AppxByPattern {
    <#
    .SYNOPSIS
        Removes AppX packages matching a pattern.
    .DESCRIPTION
        Searches for and removes installed AppX packages that match the specified pattern.
        Supports WhatIf and Confirm for safe execution.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Pattern,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Write-Log "Searching installed packages matching: $Pattern" -Level Verbose

    $cachedPackages = Get-CachedInstalledPackage
    $matchedPackages = $cachedPackages | Where-Object {
        $_.Name -like $Pattern -or $_.PackageFullName -like $Pattern
    }

    if (-not $matchedPackages) {
        return
    }

    $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

    foreach ($pkg in $matchedPackages) {
        $packageName = $pkg.PackageFullName

        if ($PSCmdlet.ShouldProcess($pkg.Name, "Remove installed AppX package")) {
            Write-Log "Removing installed package: $($pkg.Name)" -Level Info

            try {
                if ($useWindowsPowerShell) {
                    $removeScript = "Remove-AppxPackage -Package '$packageName' -AllUsers -ErrorAction Stop"
                    $null = powershell.exe -NoProfile -Command $removeScript 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Removal failed with exit code $LASTEXITCODE"
                    }
                } else {
                    Remove-AppxPackage -Package $packageName -AllUsers -ErrorAction Stop
                }
                Write-Log "Successfully removed: $packageName" -Level Success
                $Succeeded.Add("Removed: $packageName") | Out-Null
            } catch {
                Write-Log "Failed to remove $packageName : $($_.Exception.Message)" -Level Warning
                $Failed.Add("Failed: $packageName") | Out-Null
            }
        }
    }
}

function Remove-ProvisionedByPattern {
    <#
    .SYNOPSIS
        Removes provisioned AppX packages matching a pattern.
    .DESCRIPTION
        Searches for and removes provisioned AppX packages that match the specified pattern.
        Supports WhatIf and Confirm for safe execution.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Pattern,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Write-Log "Searching provisioned packages matching: $Pattern" -Level Verbose

    $cachedPackages = Get-CachedProvisionedPackage
    $provPackages = $cachedPackages | Where-Object {
        $_.PackageName -like $Pattern
    }

    if (-not $provPackages) {
        return
    }

    $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

    foreach ($p in $provPackages) {
        $packageName = $p.PackageName

        if ($PSCmdlet.ShouldProcess($packageName, "Remove provisioned AppX package")) {
            Write-Log "Removing provisioned package: $packageName" -Level Info

            try {
                if ($useWindowsPowerShell) {
                    $removeScript = "Remove-AppxProvisionedPackage -Online -PackageName '$packageName' -ErrorAction Stop"
                    $null = powershell.exe -NoProfile -Command $removeScript 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Removal failed with exit code $LASTEXITCODE"
                    }
                } else {
                    Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop
                }
                Write-Log "Successfully removed provisioned: $packageName" -Level Success
                $Succeeded.Add("Removed provisioned: $packageName") | Out-Null
            } catch {
                if ($_.Exception.Message -match "Het systeem kan het opgegeven pad niet vinden|The system cannot find the path specified") {
                    Write-Log "Provisioned package already removed: $packageName" -Level Verbose
                    $Succeeded.Add("Already removed: $packageName") | Out-Null
                } else {
                    Write-Log "Failed to remove provisioned $packageName : $($_.Exception.Message)" -Level Warning
                    $Failed.Add("Failed provisioned: $packageName") | Out-Null
                }
            }
        }
    }
}

try {
    Write-Log "========================================" -Level Info
    Write-Log "  BLOATWARE REMOVAL STARTED" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "User: $env:USERNAME" -Level Info
    Write-Log "Computer: $env:COMPUTERNAME" -Level Info
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level Info

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Log "Using Windows PowerShell for Appx operations to avoid assembly conflicts" -Level Info
    }

    $succeededRemovals = [System.Collections.ArrayList]::new()
    $failedRemovals = [System.Collections.ArrayList]::new()

    # User-visible output
    Write-UserMessage "  - Scanning for unwanted applications..." -Color Cyan

    # Remove bloatware apps
    $totalApps = $AppsToRemove.Count
    $currentApp = 0
    foreach ($appName in $AppsToRemove) {
        $currentApp++
        $pattern = "*$appName*"
        Remove-AppxByPattern -Pattern $pattern -Succeeded $succeededRemovals -Failed $failedRemovals
        Remove-ProvisionedByPattern -Pattern $pattern -Succeeded $succeededRemovals -Failed $failedRemovals
    }

    $userRemovalCount = @($succeededRemovals | Where-Object { $_ -like 'Removed:*' }).Count
    if ($userRemovalCount -gt 0) {
        Write-UserMessage "  - Removed $userRemovalCount bloatware package(s)" -Color Green
    } else {
        Write-UserMessage "  - No bloatware found (already clean)" -Color Green
    }

    # Configure registry to prevent bloatware reinstallation
    Write-UserMessage "  - Preventing automatic reinstallation..." -Color Cyan
    Write-Log "Configuring registry to prevent bloatware reinstallation..." -Level Info

    $registryConfigs = @(
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
            Name = "DisableWindowsConsumerFeatures"
            Value = 1
            Type = "DWord"
            Description = "Prevents Windows from auto-installing consumer apps"
        },
        @{
            Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "Start_IrisRecommendations"
            Value = 0
            Type = "DWord"
            Description = "Disables recommendations in Start Menu"
        }
        # IMPORTANT: The following registry keys are COMMENTED OUT by default
        # Windows has a weird bug: Setting HideRecommendedSection to 1 will remove Windows Spotlight from Settings
        # If you want to remove recommendations AND you don't care about Windows Spotlight, uncomment these:
        # @{
        #     Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        #     Name = "HideRecommendedSection"
        #     Value = 1
        #     Type = "DWord"
        #     Description = "Hides recommended section in Start Menu (breaks Windows Spotlight)"
        # },
        # @{
        #     Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education"
        #     Name = "IsEducationEnvironment"
        #     Value = 1
        #     Type = "DWord"
        #     Description = "Treats device as education environment (breaks Windows Spotlight)"
        # },
        # @{
        #     Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        #     Name = "HideRecommendedSection"
        #     Value = 1
        #     Type = "DWord"
        #     Description = "Hides recommended section in Explorer (breaks Windows Spotlight)"
        # }
    )

    foreach ($config in $registryConfigs) {
        Set-RegistryValue -Path $config.Path -Name $config.Name -Value $config.Value -Type $config.Type
    }
    Write-UserMessage "  - Protection configured successfully" -Color Green

    # Log-only summary (detailed)
    Write-Log "========================================" -Level Info
    Write-Log "  REMOVAL SUMMARY" -Level Info
    Write-Log "========================================" -Level Info

    if ($succeededRemovals.Count -gt 0) {
        Write-Log "Successfully processed $($succeededRemovals.Count) packages" -Level Success
    } else {
        Write-Log "No packages were removed" -Level Info
    }

    if ($failedRemovals.Count -gt 0) {
        Write-Log "Failed to remove $($failedRemovals.Count) packages" -Level Warning
        $failedRemovals | ForEach-Object { Write-Log "  - $_" -Level Warning }
    }

    Write-Log "Bloatware removal completed successfully" -Level Success
    Set-IntuneSuccess -AppName 'RemoveBloat' -Version '1.0.0'
    exit 0

} catch {
    Write-Log "Critical error during bloatware removal: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    Complete-Script
}
