# ============================================================================
# Install-RMMAgent.ps1
# Installs RMM/monitoring agent from USB drive.
# Place your agent installer as "Agent.exe" on USB root.
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
    $installed = $false

    # Check for RMM agent on removable drives (USB)
    $removableDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }

    foreach ($drive in $removableDrives) {
        # Look for Agent.exe or any *agent*.exe file
        $agentFiles = Get-ChildItem -Path $drive.DeviceID -Filter "*agent*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($agentFiles) {
            $agentPath = $agentFiles.FullName
            Write-DeployLog "Found agent installer on USB: $agentPath"

            try {
                Write-DeployLog "Installing agent from USB..."
                Start-Process -FilePath $agentPath -ArgumentList "/S" -WindowStyle Hidden
                Start-Sleep -Seconds 10
                Write-DeployLog "SUCCESS: Agent installation initiated. Setup will complete in background."
                $installed = $true
            } catch {
                $errorMsg = $_.Exception.Message
                Write-DeployLog "Failed to install agent from USB: $errorMsg" -IsError
            }
            break
        }
    }

    if (-not $installed) {
        Write-DeployLog "No agent installer found on USB. Skipping RMM installation."
        Write-DeployLog "To install an RMM agent, place 'Agent.exe' on your USB drive root."
    }

    exit 0
} catch {
    $errorMsg = $_.Exception.Message
    Write-DeployLog "Error: $errorMsg" -IsError
    exit 0
}
