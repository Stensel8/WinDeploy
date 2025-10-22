#requires -Version 5.1

function Test-RMMAgentInstalled {
    <#
    .SYNOPSIS
        Checks if the Datto RMM agent is installed.

    .DESCRIPTION
        Verifies both service and file existence for the RMM agent.

    .OUTPUTS
        Boolean indicating if agent is installed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $agentExePath = "C:\Program Files (x86)\CentraStage\CagService.exe"
    $fileExists = Test-Path $agentExePath

    $serviceExists = $false
    try {
        $service = Get-Service -Name "CagService" -ErrorAction SilentlyContinue
        if ($service) {
            $serviceExists = $true
        } else {
            $service = Get-Service -DisplayName "*Datto RMM*" -ErrorAction SilentlyContinue
            if ($service) {
                $serviceExists = $true
            }
        }
    } catch {
        Write-Verbose "[RMM] Service query failed: $($_.Exception.Message)"
    }

    if ($fileExists -and $serviceExists) {
        Write-Log "[RMM] Agent verified: Service running and files present" -Level Success
        return $true
    } elseif ($fileExists) {
        Write-Log "[RMM] Agent files present but service not detected" -Level Warning
        return $true
    } elseif ($serviceExists) {
        Write-Log "[RMM] Agent service detected" -Level Success
        return $true
    }

    return $false
}

function Wait-ForRMMAgentInstallation {
    <#
    .SYNOPSIS
        Waits for RMM agent installation to complete.

    .DESCRIPTION
        Polls for agent installation with configurable timeout.

    .PARAMETER MaxWaitSeconds
        Maximum time to wait for installation.

    .OUTPUTS
        Boolean indicating if agent was successfully installed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([int]$MaxWaitSeconds = 30)

    Write-Log "[RMM] Waiting for agent installation to complete (max $MaxWaitSeconds seconds)..." -Level Info

    for ($i = 1; $i -le $MaxWaitSeconds; $i++) {
        if (Test-RMMAgentInstalled) {
            Write-Log "[RMM] Agent installation confirmed after $i seconds" -Level Success
            return $true
        }

        if ($i -lt $MaxWaitSeconds) {
            Write-Log "  Checking... ($i/$MaxWaitSeconds)" -Level Verbose
            Start-Sleep -Seconds 1
        }
    }

    Write-Log "[RMM] Agent installation verification failed after $MaxWaitSeconds seconds" -Level Error
    return $false
}

function Find-RMMAgent {
    <#
    .SYNOPSIS
        Locates RMM agent executable on the system.

    .DESCRIPTION
        Searches common locations for the RMM agent installer.
        Returns path to agent or null if not found.

    .PARAMETER DownloadDirectory
        Directory where agent should be located or moved to.

    .OUTPUTS
        String path to Agent.exe or null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$DownloadDirectory = 'C:\WinDeploy\Download')

    $targetAgentPath = Join-Path $DownloadDirectory 'Agent.exe'

    if (Test-Path $targetAgentPath) {
        Write-Log "[RMM] Agent.exe already present in Download folder" -Level Success
        return $targetAgentPath
    }

    $oldAgentPath = Join-Path 'C:\WinDeploy' 'RMM-Agent.exe'
    if (Test-Path $oldAgentPath) {
        Write-Log "[RMM] Found RMM-Agent.exe, moving to Download folder as Agent.exe..." -Level Info
        try {
            Move-Item -Path $oldAgentPath -Destination $targetAgentPath -Force
            Write-Log "[RMM] Agent moved successfully" -Level Success
            return $targetAgentPath
        } catch {
            Write-Log "[RMM] Failed to move agent: $_" -Level Error
        }
    }

    $searchPaths = @('C:\WinDeploy', 'D:\', 'E:\', 'F:\', 'G:\', 'H:\')
    foreach ($path in $searchPaths) {
        if (!(Test-Path $path)) { continue }

        $agents = Get-ChildItem -Path $path -Filter "*Agent*.exe" -File -ErrorAction SilentlyContinue
        if ($agents) {
            $agent = $agents | Select-Object -First 1
            Write-Log "[RMM] Agent found: $($agent.FullName)" -Level Success
            Write-Log "[RMM] Moving to Download folder as Agent.exe..." -Level Info

            try {
                Copy-Item -Path $agent.FullName -Destination $targetAgentPath -Force
                Write-Log "[RMM] Agent copied successfully" -Level Success
                return $targetAgentPath
            } catch {
                Write-Log "[RMM] Failed to copy agent: $_" -Level Error
            }
        }
    }

    Write-Log "[RMM] No RMM agent found" -Level Warning
    return $null
}

function Install-RMMAgent {
    <#
    .SYNOPSIS
        Installs the Datto RMM agent.

    .DESCRIPTION
        Locates and installs the RMM agent if not already present.
        Returns true if installed successfully or already installed.

    .PARAMETER DownloadDirectory
        Directory where agent installer is located.

    .OUTPUTS
        Boolean indicating installation success.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$DownloadDirectory = 'C:\WinDeploy\Download')

    Write-Log "========================================" -Level Info
    Write-Log "  INSTALLING RMM AGENT" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "[RMM] Checking if agent is already installed..." -Level Info

    if (Test-RMMAgentInstalled) {
        Write-Log "[RMM] Agent is already installed" -Level Success
        return $true
    }

    Write-Log "[RMM] Searching agent package..." -Level Info
    $agentPath = Find-RMMAgent -DownloadDirectory $DownloadDirectory

    if (!$agentPath -or !(Test-Path $agentPath)) {
        Write-Log "[RMM] Cannot install - Agent.exe not found" -Level Warning
        return $false
    }

    Write-Log "[RMM] Agent package found: $agentPath" -Level Success
    Write-Log "[RMM] Starting agent installation..." -Level Info
    Write-Log "[RMM] Executing silent installation..." -Level Info

    try {
        Start-Process -FilePath $agentPath -ArgumentList "/S", "/v/qn" -PassThru -NoNewWindow | Out-Null

        Write-Log "[RMM] Waiting for installation to complete..." -Level Info
        $installed = Wait-ForRMMAgentInstallation -MaxWaitSeconds 30

        if ($installed) {
            Write-Log "[RMM] Agent installation successful" -Level Success
            return $true
        } else {
            Write-Log "[RMM] Agent installation failed or timed out" -Level Error
            return $false
        }
    } catch {
        Write-Log "[RMM] Agent installation error: $_" -Level Error
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-RMMAgentInstalled',
    'Wait-ForRMMAgentInstallation',
    'Find-RMMAgent',
    'Install-RMMAgent'
)
