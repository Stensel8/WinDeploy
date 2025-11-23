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

Function Test-DattoRMMInstalled {
    # Check multiple indicators of Datto RMM presence
    $indicators = @(
        (Test-Path "C:\Program Files (x86)\CentraStage\CagService.exe"),
        (Test-Path "C:\Program Files (x86)\CentraStage"),
        (Get-Service -Name "CagService" -ErrorAction SilentlyContinue),
        (Get-Process -Name "CagService" -ErrorAction SilentlyContinue),
        (Test-Path "HKLM:\SOFTWARE\CentraStage" -ErrorAction SilentlyContinue)
    )
    
    $found = @($indicators | Where-Object { $_ -ne $null -and $_ -ne $false })
    return $found.Count -gt 0
}

try {
    # Site ID for fallback download (replace with your actual site ID)
    $SiteID = "EnterYourIDHere"
    $installed = $false

    # Check if Datto RMM is already installed
    if (Test-DattoRMMInstalled) {
        Write-DeployLog "Datto RMM is already installed. Skipping installation."
        exit 0
    }

    # Check for RMM agent on removable drives (USB)
    $removableDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }  # DriveType 2 = Removable
    foreach ($drive in $removableDrives) {
        $agentFiles = Get-ChildItem -Path $drive.DeviceID -Filter "*agent*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($agentFiles) {
            $agentPath = $agentFiles.FullName
            Write-DeployLog "Found RMM agent on USB: $agentPath"
            try {
                # Install from USB (fire and forget)
                Write-DeployLog "Installing RMM agent from USB..."
                Start-Process -FilePath $agentPath -ArgumentList "/S" -WindowStyle Hidden
                
                # Wait 10 seconds and check for Datto RMM indicators
                Start-Sleep -Seconds 10
                
                if (Test-DattoRMMInstalled) {
                    Write-DeployLog "SUCCESS: Datto RMM installation started successfully. Agent will complete setup."
                    $installed = $true
                } else {
                    Write-DeployLog "WARNING: No Datto RMM indicators detected after 10 seconds. Installation may be slow or failed."
                }
            } catch {
                $errorMsg = $_.Exception.Message
                Write-DeployLog "Failed to install RMM agent from USB: $errorMsg" -IsError
            }
            break
        }
    }

    if (-not $installed) {
        # Fallback: Download from Datto
        if ($SiteID -ne "EnterYourIDHere") {
            Write-DeployLog "No RMM agent found on USB. Attempting download..."
            $Url = "https://pinotage.rmm.datto.com/download-agent/windows/$SiteID"
            $InstallerPath = Join-Path $env:TEMP "AgentInstall.exe"

            try {
                $WebClient = New-Object System.Net.WebClient
                $WebClient.DownloadFile($Url, $InstallerPath)
                Write-DeployLog "Downloaded RMM installer to $InstallerPath"

                # Install silently (fire and forget)
                Write-DeployLog "Installing RMM agent from download..."
                Start-Process -FilePath $InstallerPath -ArgumentList "/S" -WindowStyle Hidden
                
                # Wait 10 seconds and check for Datto RMM indicators
                Start-Sleep -Seconds 10
                
                if (Test-DattoRMMInstalled) {
                    Write-DeployLog "SUCCESS: Datto RMM installation started successfully. Agent will complete setup."
                    $installed = $true
                } else {
                    Write-DeployLog "WARNING: No Datto RMM indicators detected after 10 seconds. Installation may be slow or failed."
                }

                # Clean up installer
                try {
                    if (Test-Path $InstallerPath) {
                        Remove-Item -Path $InstallerPath -Force -ErrorAction Stop
                        Write-DeployLog "Removed installer at $InstallerPath"
                    }
                } catch {
                    $errorMsg = $_.Exception.Message
                    Write-DeployLog "Failed to remove installer at ${InstallerPath}: $errorMsg"
                }
            } catch {
                $errorMsg = $_.Exception.Message
                Write-DeployLog "Failed to download or install RMM agent: $errorMsg" -IsError
            }
        } else {
            Write-DeployLog "SiteID not configured, skipping download."
        }
    }

    if ($installed) {
        Write-DeployLog "RMM agent installation initiated successfully."
    } else {
        Write-DeployLog "RMM agent installation skipped or failed."
    }
    exit 0
} catch {
    $errorMsg = $_.Exception.Message
    Write-DeployLog "Error: $errorMsg" -IsError
    Write-Error "RMM agent installation partial - continuing."
    exit 0
}