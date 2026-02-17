# ============================================================================
# Remove-Bloat.ps1
# Removes common bloatware apps and prevents reinstall.
# Standalone script - can be deployed via any management tool.
# ============================================================================

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = Join-Path $env:TEMP "WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Host $Message }
}

# Expanded list for common bloatware (inspired by WinDeploy Remove-Bloat.ps1, excluding Get Help)
$BloatwareList = @(
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
    # "Microsoft.GetHelp",  # Excluded: Required for Windows troubleshooting/support
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
    # "Microsoft.WebExperiencePack",  # Do not remove to preserve Windows Spotlight functionality
    "Microsoft.549981C3F5F10",

    # AI and Assistant
    "Microsoft.Copilot",

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

try {
    Write-DeployLog "=== Bloatware Removal ==="

    $Removed = 0

    # Get all provisioned packages once
    try {
        $ProvisionedPackages = Get-AppxProvisionedPackage -Online
    } catch {
        $ProvisionedPackages = $null
        Write-DeployLog "Failed to retrieve provisioned packages: $($_.Exception.Message)" -IsError
    }

    # Remove provisioned (for new users)
    Write-DeployLog "Removing provisioned packages..."
    foreach ($App in $BloatwareList) {
        if ($ProvisionedPackages) {
            $Pkgs = $ProvisionedPackages | Where-Object { $_.DisplayName -like "*$App*" }
            foreach ($Pkg in $Pkgs) {
                Remove-AppxProvisionedPackage -Online -PackageName $Pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                if ($?) {
                    $Removed++
                    $PkgMsg = "Removed provisioned: $($Pkg.DisplayName)"
                    Write-DeployLog $PkgMsg
                } else {
                    $FailMsg = "Failed to remove provisioned: $($Pkg.DisplayName)"
                    Write-DeployLog $FailMsg -IsError
                }
            }
        }
        # No logging if no packages found (suppressed as requested)
    }

    # Get all installed packages once
    try {
        $InstalledPackages = Get-AppxPackage -AllUsers
    } catch {
        $InstalledPackages = $null
        Write-DeployLog "Failed to retrieve installed packages: $($_.Exception.Message)" -IsError
    }

    # Remove installed
    Write-DeployLog "Removing installed packages..."
    foreach ($App in $BloatwareList) {
        if ($InstalledPackages) {
            $Pkgs = $InstalledPackages | Where-Object { $_.Name -like "*$App*" }
            foreach ($Pkg in $Pkgs) {
                Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                if ($?) {
                    $Removed++
                    $PkgMsg = "Removed installed: $($Pkg.Name)"
                    Write-DeployLog $PkgMsg
                } else {
                    $FailMsg = "Failed to remove installed: $($Pkg.Name)"
                    Write-DeployLog $FailMsg -IsError
                }
            }
        }
        # No logging if no packages found (suppressed as requested)
    }







    $SuccessMsg = "SUCCESS: Removed $Removed apps."
    Write-DeployLog $SuccessMsg


    Write-Output ""
    Write-Output "========================================"
    Write-Output "  Additional scripts and tweaks..."
    Write-Output "========================================"
    Write-Output "Windows Spotlight: If you are experiencing issues with Windows Spotlight, ensure that Start menu recommendations are enabled."
    Write-Output "If you are still experiencing issues and want to use the Spotlight features for dynamic wallpapers, use the Fix-Spotlight.ps1 script."
    Write-Output "This script is available as an optional download: C:\WinDeploy\Download\Fix-Spotlight.ps1"

    # Note: Bloatware may be reinstalled with future Windows Updates. For more control, consider using Winutil: https://github.com/ChrisTitusTech/winutil
    Write-DeployLog "Note: Bloatware may be reinstalled with future Windows Updates. For more control, consider using Winutil: `e]8;;https://github.com/ChrisTitusTech/winutil`e\https://github.com/ChrisTitusTech/winutil`e]8;;`e\"
    exit 0
} catch {
    $ErrMsg = $_.Exception.Message
    Write-DeployLog "Error: $ErrMsg" -IsError
    Write-Error "Bloatware partial - continuing."
    exit 0
}
