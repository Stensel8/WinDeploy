# ============================================================================
# Install-Applications.ps1
# Installs applications via WinGet package manager.
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

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

try {

    $Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        #"Adobe.Acrobat.Reader.64-bit", #Uncomment if you need Adobe Reader
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip",
        "Microsoft.WindowsApp",
        "Microsoft.CompanyPortal"
    )

    #Note: Some applications fail to install. This is why we have a separate list for msstore apps.
    $MsStoreApplications = @(
        #"XPDP273C0XHQH2", #Adobe Acrobat Reader (msstore) #Uncomment if you need Adobe Reader
        "XP8BT8DW290MPQ", # Microsoft Teams (msstore)
        "9N1F85V9T8BN", # Windows App (msstore)
        "9WZDNCRFJ3PZ" # Company Portal (msstore)
    )

    foreach ($app in $Applications) {
        Write-DeployLog "Installing $app..."
        try {
            $process = Start-Process winget -ArgumentList "install --id $app --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-DeployLog "Installed $app"
            } else {
                Write-DeployLog "Failed to install $app (exit code $($process.ExitCode))" -IsError
            }
        } catch {
            Write-DeployLog "Failed to install $app" -IsError
        }
    }

    foreach ($app in $MsStoreApplications) {
        Write-DeployLog "Installing msstore $app..."
        try {
            $process = Start-Process winget -ArgumentList "install --id $app --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-DeployLog "Installed msstore $app"
            } else {
                Write-DeployLog "Failed to install msstore $app (exit code $($process.ExitCode))" -IsError
            }
        } catch {
            Write-DeployLog "Failed to install msstore $app" -IsError
        }
    }

    Write-DeployLog "SUCCESS: Application installation done."
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "Application installation partial - continuing."
    exit 0
}