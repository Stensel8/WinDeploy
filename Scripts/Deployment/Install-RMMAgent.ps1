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

Function Wait-ForRMMService {
    param([int]$TimeoutSeconds = 60)
    Write-DeployLog "Waiting for RMM service to start..."
    $startTime = Get-Date
    do {
        $cagService = Get-Service -Name "CagService" -ErrorAction SilentlyContinue
        if ($cagService) {
            if ($cagService.Status -eq 'Running') {
                Write-DeployLog "RMM service is running."
                return $true
            } elseif ($cagService.Status -eq 'Stopped') {
                Write-DeployLog "Starting RMM service..."
                try {
                    Start-Service -Name "CagService" -ErrorAction Stop
                    Write-DeployLog "RMM service started."
                    return $true
                } catch {
                    Write-DeployLog "Failed to start RMM service: $($_.Exception.Message)" -IsError
                }
            }
        }
        Start-Sleep -Seconds 5
        $elapsed = (Get-Date) - $startTime
    } while ($elapsed.TotalSeconds -lt $TimeoutSeconds)
    Write-DeployLog "Timeout waiting for RMM service." -IsError
    return $false
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
        $cagService = Get-Service -Name "CagService" -ErrorAction SilentlyContinue
        if ($cagService -and $cagService.Status -eq 'Running') {
            Write-DeployLog "Datto RMM is already installed and running. Skipping installation."
            $installed = $true
        } elseif ($cagService -and $cagService.Status -eq 'Stopped') {
            Write-DeployLog "Datto RMM is installed but stopped. Starting service..."
            try {
                Start-Service -Name "CagService" -ErrorAction Stop
                Write-DeployLog "Datto RMM service started."
                $installed = $true
            } catch {
                Write-DeployLog "Failed to start existing Datto RMM service: $($_.Exception.Message)" -IsError
            }
        } else {
            Write-DeployLog "Datto RMM indicators present but service not found. Proceeding with installation."
        }
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
                    Start-Sleep -Seconds 10
                    if ((Test-Path "C:\Program Files (x86)\CentraStage") -and (Test-Path "HKLM:\SOFTWARE\CentraStage")) {
                        Write-DeployLog "RMM agent installed from USB."
                        $installed = $true
                        Wait-ForRMMService
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
                    Start-Sleep -Seconds 10
                    if ((Test-Path "C:\Program Files (x86)\CentraStage") -and (Test-Path "HKLM:\SOFTWARE\CentraStage")) {
                        Write-DeployLog "RMM agent installed via download."
                        $installed = $true
                        Wait-ForRMMService
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
