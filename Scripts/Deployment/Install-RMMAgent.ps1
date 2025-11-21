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

    # Check if Datto RMM is already installed (by filesystem/registry or service)
    Write-DeployLog "Checking if RMM agent is already installed..."

    Function Get-RMMAgentInstalled {
        # Check by filesystem + registry
        if ((Test-Path "C:\Program Files (x86)\CentraStage") -and (Test-Path "HKLM:\SOFTWARE\CentraStage")) { return $true }
        # Check for Datto service (CagService is Datto's service name in many distributions)
        if (Get-Service -Name 'CagService' -ErrorAction SilentlyContinue) { return $true }
        return $false
    }

    $dirExists = Test-Path "C:\Program Files (x86)\CentraStage"
    $regExists = Test-Path "HKLM:\SOFTWARE\CentraStage"
    Write-DeployLog "Directory 'C:\Program Files (x86)\CentraStage' exists: $dirExists"
    Write-DeployLog "Registry 'HKLM:\SOFTWARE\CentraStage' exists: $regExists"

    if (Get-RMMAgentInstalled) {
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
                    # Install from USB - simpler approach (Datto-style) and don't rely on installer exit codes
                    Write-DeployLog "Installing RMM agent from USB..."
                    try { & "$agentPath" '/S' | Out-Null } catch { Write-DeployLog "Call operator failed to start installer: $($_.Exception.Message)" -IsError }

                    # Wait (poll) for installation indicators (give installer more time)
                    $timeout = 300
                    $counter = 0
                    Write-Output "Counting to $timeout...."
                    do {
                        $counter++
                        Write-Output "$counter.."
                        if (Get-RMMAgentInstalled) {
                            Write-Output "Agent found. Continuing deployment."
                            $installed = $true
                            break
                        }
                        Start-Sleep -Seconds 1
                    } while ($counter -lt $timeout)

                    if (-not $installed) {
                        Write-DeployLog "Installation indicators not found after USB install within $timeout seconds." -IsError
                    }
                } catch {
                    Write-DeployLog "Failed to install RMM agent from USB: $($_.Exception.Message)" -IsError
                }
                break
            }
        }

        if (-not $installed) {
            # Fallback: Download from Datto (only if SiteID configured)
            if ($SiteID -ne "EnterYourIDHere") {
                Write-DeployLog "No RMM agent found on USB. Attempting download..."
                $Url = "https://pinotage.rmm.datto.com/download-agent/windows/$SiteID"
                $InstallerPath = "$env:TEMP\AgentInstall.exe"

                try {
                    # Ensure TLS1.2 for secure download
                    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { Write-DeployLog "Failed to set TLS1.2 - proceeding with default security protocol: $($_.Exception.Message)" -IsError }

                    $WebClient = New-Object System.Net.WebClient
                    $WebClient.DownloadFile($Url, $InstallerPath)
                    Write-DeployLog "Downloaded RMM installer to $InstallerPath"

                    # Install downloaded package (simple synchronous call) and do not rely on installer exit codes
                    Write-DeployLog "Running downloaded installer..."
                    try { & "$InstallerPath" '/S' | Out-Null } catch { Write-DeployLog "Downloaded installer returned error on call operator: $($_.Exception.Message)" -IsError }

                    # Remove installer after attempting install
                    try { Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue } catch { Write-DeployLog "Failed to remove installer at $InstallerPath: $($_.Exception.Message)" -IsError }

                    # Wait for installation indicators
                    $timeout = 300
                    $counter = 0
                    Write-Output "Counting to $timeout...."
                    do {
                        $counter++
                        Write-Output "$counter.."
                        if (Get-RMMAgentInstalled) {
                            Write-Output "Agent found. Continuing deployment."
                            $installed = $true
                            break
                        }
                        Start-Sleep -Seconds 1
                    } while ($counter -lt $timeout)

                    if (-not $installed) {
                        Write-DeployLog "Installation indicators not found after download install within $timeout seconds." -IsError
                    }
                } catch {
                    Write-DeployLog "Failed to download or install RMM agent: $($_.Exception.Message)" -IsError
                }
            } else {
                Write-DeployLog "SiteID not configured in expected variable"
            }
        }
    }

    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "RMM agent installation Failed - continuing."
    exit 0
}
