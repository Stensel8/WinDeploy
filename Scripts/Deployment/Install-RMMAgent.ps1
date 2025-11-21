# ============================================================================
# Install-RMMAgent.ps1
# Installs RMM agent from USB or via download fallback.
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
    # Site ID for fallback download (replace with your actual site ID)
    $SiteID = "EnterYourIDHere"
    $installed = $false

    # Check if Datto RMM is already installed
    Write-DeployLog "Checking if RMM agent is already installed..."
    $dirExists = Test-Path "C:\Program Files (x86)\CentraStage"
    $regExists = Test-Path "HKLM:\SOFTWARE\CentraStage"
    Write-DeployLog "Directory 'C:\Program Files (x86)\CentraStage' exists: $dirExists"
    Write-DeployLog "Registry 'HKLM:\SOFTWARE\CentraStage' exists: $regExists"
    if ($dirExists -and $regExists) {
        Write-DeployLog "Datto RMM is already installed. Skipping installation."
        $installed = $true
    }
    if (-not $installed) {
        if ($SiteID -eq "EnterYourIDHere") {
            Write-DeployLog "SiteID not configured in expected variable"
        }
        # Check for RMM agent on removable drives (USB)
        Write-DeployLog "Checking for USBs containing *Agent*.exe...."
        $removableDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }  # DriveType 2 = Removable
        foreach ($drive in $removableDrives) {
            $agentFiles = Get-ChildItem -Path $drive.DeviceID -Filter "*agent*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($agentFiles) {
                $agentPath = $agentFiles.FullName
                Write-DeployLog "Found RMM agent on USB: $agentPath"
                try {
                    # Install from USB
                    Write-DeployLog "Installing RMM agent from USB..."
                    Start-Process -FilePath $agentPath -ArgumentList "/S" -WindowStyle Hidden
                    Start-Sleep -Seconds 15
                    if ((Test-Path "C:\Program Files (x86)\CentraStage") -and (Test-Path "HKLM:\SOFTWARE\CentraStage")) {
                        Write-DeployLog "RMM agent installed from USB."
                        $installed = $true
                    } else {
                        Write-DeployLog "Installation indicators not found after USB install." -IsError
                    }
                } catch {
                    Write-DeployLog "Failed to install RMM agent from USB: $($_.Exception.Message)" -IsError
                }
                break
            }
        }

        if (-not $installed) {
            # Fallback: Download from Datto
            if ($SiteID -ne "EnterYourIDHere") {
                Write-DeployLog "No RMM agent found on USB. Attempting download..."
                $Url = "https://pinotage.rmm.datto.com/download-agent/windows/$SiteID"
                $InstallerPath = "$env:TEMP\AgentInstall.exe"

                try {
                    $WebClient = New-Object System.Net.WebClient
                    $WebClient.DownloadFile($Url, $InstallerPath)
                    Write-DeployLog "Downloaded RMM installer to $InstallerPath"

                    # Install silently
                    Start-Process -FilePath $InstallerPath -ArgumentList "/S" -WindowStyle Hidden
                    Start-Sleep -Seconds 15
                    if ((Test-Path "C:\Program Files (x86)\CentraStage") -and (Test-Path "HKLM:\SOFTWARE\CentraStage")) {
                        Write-DeployLog "RMM agent installed via download."
                        $installed = $true
                    } else {
                        Write-DeployLog "Installation indicators not found after download install." -IsError
                    }
                } catch {
                    Write-DeployLog "Failed to download or install RMM agent: $($_.Exception.Message)" -IsError
                }
            } else {
                Write-DeployLog "SiteID not configured in expected variable"
            }
        }
    }

    if ($installed) {
        Write-DeployLog "SUCCESS: RMM agent installation done."
    } else {
        Write-DeployLog "RMM agent installation skipped or failed."
    }
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "RMM agent installation Failed - continuing."
    exit 0
}
