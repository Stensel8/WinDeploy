# ============================================================================
# Remove-Bloat.ps1
# Removes common bloatware apps and prevents reinstall.
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
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

Write-Output "Starting bloatware removal."

# Expanded list for common bloatware (inspired by WinDeploy Remove-Bloat.ps1, excluding Get Help)
$BloatwareList = @(
    # Microsoft Communication and Social
    "Microsoft.SkypeApp", "Microsoft.YourPhone", "Microsoft.People", "Microsoft.Messaging",

    # Microsoft Media and Entertainment
    "Microsoft.GamingApp", "Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay", "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.Media.Player", "Microsoft.WindowsMaps",

    # Microsoft Productivity and Tools
    "Microsoft.Todos", "Microsoft.MicrosoftStickyNotes", "Microsoft.OneConnect",
    "Microsoft.Getstarted", "Microsoft.WindowsFeedbackHub", "Microsoft.Microsoft3DViewer",
    "Microsoft.3DBuilder", "Microsoft.Print3D", "Microsoft.MixedReality.Portal",
    "Microsoft.Clipchamp", "Clipchamp.Clipchamp", "9P1J8S7CCWWT", "MicrosoftCorporationII.MicrosoftFamily",
    "Microsoft.WindowsAlarms", "Microsoft.ScreenSketch", "Microsoft.Wallet",
    "Microsoft.NetworkSpeedTest", "Microsoft.MicrosoftJournal", "Microsoft.Office.Sway",

    # Microsoft News, Weather, and Information
    "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.BingFinance",
    "Microsoft.BingHealthAndFitness", "Microsoft.BingSports", "Microsoft.BingTranslator",
    "Microsoft.News", "Microsoft.Start", "Microsoft.BingSearch", "Microsoft.WebExperiencePack",
    "Microsoft.549981C3F5F10",

    # Microsoft AI and Assistant
    "Microsoft.Copilot",

    # Third-Party Social and Streaming
    "Facebook.Facebook", "Instagram", "Twitter", "TikTok", "LinkedInforWindows",
    "SpotifyAB.SpotifyMusic", "Netflix", "Disney", "AmazonVideo.PrimeVideo",

    # Third-Party Games
    "king.com.CandyCrushSaga", "king.com.CandyCrushSodaSaga", "king.com.BubbleWitch3Saga"
)

try {
    Write-DeployLog "=== Bloatware Removal ==="

    $Removed = 0

    # Remove provisioned (for new users)
    Write-DeployLog "Removing provisioned packages..."
    foreach ($App in $BloatwareList) {
        $Pkgs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$App*" }
        if ($Pkgs) {
            foreach ($Pkg in $Pkgs) {
                Remove-AppxProvisionedPackage -Online -PackageName $Pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                if ($?) {
                    $Removed++
                    $PkgMsg = "Removed provisioned: $($Pkg.DisplayName)"
                    Write-DeployLog $PkgMsg
                    Write-Output $PkgMsg
                } else {
                    $FailMsg = "Failed to remove provisioned: $($Pkg.DisplayName)"
                    Write-DeployLog $FailMsg -IsError
                    Write-Error $FailMsg
                }
            }
        }
        # No logging if no packages found (suppressed as requested)
    }

    # Remove installed
    Write-DeployLog "Removing installed packages..."
    foreach ($App in $BloatwareList) {
        $Pkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$App*" }
        if ($Pkgs) {
            foreach ($Pkg in $Pkgs) {
                Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                if ($?) {
                    $Removed++
                    $PkgMsg = "Removed installed: $($Pkg.Name)"
                    Write-DeployLog $PkgMsg
                    Write-Output $PkgMsg
                } else {
                    $FailMsg = "Failed to remove installed: $($Pkg.Name)"
                    Write-DeployLog $FailMsg -IsError
                    Write-Error $FailMsg
                }
            }
        }
        # No logging if no packages found (suppressed as requested)
    }

    # Prevent reinstall - fixed registry path and added more policies
    Write-DeployLog "Setting anti-reinstall..."
    $RegPaths = @(
        @{
            Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            Value = 'DisableWindowsConsumerFeatures'
            Data = 1
        },
        @{
            Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            Value = 'DisableConsumerFeaturesThroughWindowsUpdates'
            Data = 1
        },
        @{
            Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Value = 'Start_IrisRecommendations'
            Data = 0
        }
    )

    foreach ($Reg in $RegPaths) {
        $RegResult = reg add "$($Reg.Path)" /v $Reg.Value /t REG_DWORD /d $Reg.Data /f 2>&1
        if ($LASTEXITCODE -ne 0) {
            $RegErr = "Registry failed for $($Reg.Value): $RegResult"
            Write-DeployLog $RegErr -IsError
            Write-Error $RegErr
        } else {
            Write-DeployLog "Set policy: $($Reg.Value)"
            Write-Output "Set policy: $($Reg.Value)"
        }
    }

    $SuccessMsg = "SUCCESS: Removed $Removed apps."
    Write-DeployLog $SuccessMsg
    Write-Output "Bloatware removal done: $Removed apps."
    exit 0
} catch {
    $ErrMsg = $_.Exception.Message
    Write-DeployLog "Error: $ErrMsg" -IsError
    Write-Error "Bloatware partial - continuing."
    exit 0
}
