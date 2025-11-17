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
        #"Adobe.Acrobat.Reader.64-bit",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip",
        "Microsoft.WindowsApp",
        "Microsoft.CompanyPortal"
    )

    foreach ($app in $Applications) {
        Write-DeployLog "Installing $app..."
        try {
            winget install --id $app --silent --accept-package-agreements --accept-source-agreements
            Write-DeployLog "Installed $app"
        } catch {
            Write-DeployLog "Failed to install $app" -IsError
        }
    }

    Write-DeployLog "SUCCESS: Application installation done."
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "Application installation partial - continuing."
    exit 0
}