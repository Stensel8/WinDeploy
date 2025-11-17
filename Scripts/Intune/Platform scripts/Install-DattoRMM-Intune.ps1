# ============================================================================
# Install-DattoRMM-Intune.ps1
# Installs Datto RMM agent via direct download for Intune/Autopilot device prep.
# Compatible: Intune Platform Scripts (SYSTEM context only).
# ============================================================================

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Output $Message }
}

# Download installer
$Url = "https://pinotage.rmm.datto.com/download-agent/windows/EnterYourIDHere"
$InstallerPath = "$env:TEMP\AgentInstall.exe"
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($Url, $InstallerPath)

Write-DeployLog "Downloaded Datto RMM installer to $InstallerPath"

# Install silently
Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -WindowStyle Hidden

Write-DeployLog "Installed Datto RMM agent"

# Always exit 0 to avoid breaking deployment or signaling reboots
exit 0
