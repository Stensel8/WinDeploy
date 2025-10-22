#requires -Version 5.1

function Get-RemoteScript {
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Single')]
        [string]$ScriptName,

        [Parameter(ParameterSetName = 'Single')]
        [string]$ScriptUrl,

        [Parameter(ParameterSetName = 'Single')]
        [string]$SavePath,

        [Parameter(ParameterSetName = 'Single')]
        [string]$ExpectedHash,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$DownloadAll,

        [string]$Version,
        [string]$BaseUrl,
        [string]$DownloadDir = 'C:\WinDeploy\Download',
        [int]$MaxRetries = 3
    )

    # Determine version to use
    if (-not $Version) {
        # Try to read VERSION file from multiple locations
        $versionLocations = @(
            (Join-Path $PSScriptRoot '..\..\VERSION'),
            'C:\WinDeploy\Download\VERSION',
            'C:\WinDeploy\VERSION'
        )

        foreach ($versionPath in $versionLocations) {
            if (Test-Path $versionPath) {
                $Version = (Get-Content $versionPath -Raw).Trim()
                Write-Log "Using version from file: $Version" -Level Verbose
                break
            }
        }

        # Fallback to main branch if no VERSION file found
        if (-not $Version) {
            $Version = 'main'
            Write-Log "No VERSION file found, defaulting to main branch" -Level Verbose
        }
    }

    # Build BaseUrl if not explicitly provided
    if (-not $BaseUrl) {
        if ($Version -eq 'main') {
            $BaseUrl = "https://raw.githubusercontent.com/Stensel8/WinDeploy/refs/heads/main/Scripts"
        } else {
            $BaseUrl = "https://raw.githubusercontent.com/Stensel8/WinDeploy/$Version/Scripts"
        }
        Write-Log "Using BaseUrl: $BaseUrl" -Level Verbose
    }
    # Ensure download directory exists
    if (-not (Test-Path $DownloadDir)) {
        $null = New-Item -Path $DownloadDir -ItemType Directory -Force
    }

    # Handle DownloadAll mode
    if ($DownloadAll) {
        $allScripts = @(
            'Deploy-Device.ps1', 'DisableFirstLogonAnimation.ps1',
            'Get-InstalledSoftware.ps1', 'Generate-Hostname.ps1', 'Init-Deployment.ps1',
            'Install-Applications.ps1', 'Install-Drivers.ps1', 'Install-MSI.ps1',
            'Install-PowerShell7.ps1', 'Install-WindowsUpdates.ps1', 'Install-Winget.ps1',
            'OOBE-Requirement.ps1', 'Remove-Bloat.ps1', 'Set-Theme.ps1', 'Update-AllApps.ps1'
        )

        $missingScripts = @()
        foreach ($script in $allScripts) {
            $localPath = Join-Path $DownloadDir $script
            if (-not (Test-Path $localPath)) {
                $missingScripts += $script
            }
        }

        if ($missingScripts.Count -eq 0) {
            return $true
        }

        $successCount = 0
        $failCount = 0

        foreach ($script in $missingScripts) {
            $url = "$BaseUrl/$script"
            $path = Join-Path $DownloadDir $script

            if (Get-RemoteScript -ScriptUrl $url -SavePath $path -MaxRetries $MaxRetries) {
                $successCount++
            } else {
                $failCount++
            }
        }

        return ($failCount -eq 0)
    }

    # Handle single script download
    if (-not $ScriptUrl -and $ScriptName) {
        $ScriptUrl = "$BaseUrl/$ScriptName"
    }
    if (-not $SavePath -and $ScriptName) {
        $SavePath = Join-Path $DownloadDir $ScriptName
    }
    if (-not $ScriptUrl -or -not $SavePath) {
        Write-Log "ScriptUrl and SavePath or ScriptName required" -Level Error
        return $false
    }
    $directory = Split-Path $SavePath -Parent
    if (-not (Test-Path $directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }
    $attempt = 0
    do {
        $attempt++
        try {
            Write-Log "Downloading from $ScriptUrl (attempt $attempt/$MaxRetries)" -Level Info
            try {
                Import-Module BitsTransfer -ErrorAction Stop
                Start-BitsTransfer -Source $ScriptUrl -Destination $SavePath -ErrorAction Stop
                Write-Log "Downloaded using BITS" -Level Verbose
            } catch {
                $webClient = New-Object System.Net.WebClient
                $webClient.Encoding = [System.Text.Encoding]::UTF8
                $content = $webClient.DownloadString($ScriptUrl)
                [System.IO.File]::WriteAllText($SavePath, $content, (New-Object System.Text.UTF8Encoding $false))
                $webClient.Dispose()
            }
            if ($ExpectedHash) {
                $fileHash = (Get-FileHash -Path $SavePath -Algorithm SHA256).Hash
                if ($fileHash -ne $ExpectedHash) {
                    Remove-Item -Path $SavePath -Force -ErrorAction SilentlyContinue
                    throw "Hash mismatch"
                }
                Write-Log "Hash verified" -Level Success
            }
            Write-Log "Download successful: $(Split-Path $SavePath -Leaf)" -Level Success
            return $true
        } catch {
            if ($attempt -ge $MaxRetries) {
                Write-Log "Download failed after $MaxRetries attempts: $_" -Level Error
                return $false
            }
            Write-Log "Attempt $attempt failed: $_" -Level Warning
            Start-Sleep -Seconds 5
        }
    } while ($attempt -lt $MaxRetries)
    return $false
}

Export-ModuleMember -Function @('Get-RemoteScript')