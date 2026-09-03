# ============================================================================
# Install-WindowsUpdates.ps1
# Installs all available Windows Updates.
# Standalone script - can be deployed via any management tool.
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Warning $Message } else { Write-Output $Message }
}

try {

    # Trust PSGallery to avoid prompts (best-effort)
    try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { Write-Warning "Failed to trust PSGallery: $($_.Exception.Message)" }

    # Install PSWindowsUpdate module if not present
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        # Install NuGet provider if needed (required for PowerShell Gallery modules)
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false | Out-Null
            } catch {
                Write-Warning "Failed to install NuGet provider: $($_.Exception.Message)"
            }
        }

        try {
            Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers
            Write-DeployLog "Installed PSWindowsUpdate module"
        } catch {
            Write-DeployLog "Failed to install PSWindowsUpdate module" -IsError
            exit 1
        }
    }

    Import-Module PSWindowsUpdate -Force

    Write-DeployLog "Verifying Windows Update service..."
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if (-not $wuService) {
        Write-DeployLog "Windows Update service (wuauserv) not found on this system." -IsError
        exit 1
    }
    if ($wuService.Status -ne 'Running') {
        Write-DeployLog "Starting Windows Update service..."
        Start-Service -Name wuauserv -ErrorAction Stop
        Start-Sleep -Seconds 3
    }

    Write-DeployLog "Scanning for available updates..."
    $updates = Get-WindowsUpdate -MicrosoftUpdate
    if (-not $updates -or $updates.Count -eq 0) {
        Write-DeployLog "No updates available. System is up to date!"
        exit 0
    }

    Write-DeployLog "Found $($updates.Count) update(s)"
    foreach ($update in $updates) {
        Write-DeployLog "  - $($update.Title)"
    }

    Write-DeployLog "Downloading and installing updates. This can take a while..."
    $installedCount = 0
    $failedCount = 0

    try {
        $results = @(Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -IgnoreReboot -Confirm:$false -ErrorAction Stop)
    } catch {
        Write-DeployLog "Update installation failed: $($_.Exception.Message)" -IsError
        $results = @()
        $failedCount = $updates.Count
    }

    foreach ($result in $results) {
        $title  = if ($result.PSObject.Properties.Name -contains 'Title')  { $result.Title }  else { 'Unknown update' }
        $status = if ($result.PSObject.Properties.Name -contains 'Result') { $result.Result } else { 'Unknown' }
        if ($status -match 'Installed|Succeeded') {
            Write-DeployLog "  - Installed: $title"
            $installedCount++
        } else {
            Write-DeployLog "  - $status`: $title" -IsError
            $failedCount++
        }
    }

    Write-DeployLog "Installation complete. Installed: $installedCount, Failed: $failedCount"
    if ($failedCount -eq 0) {
        Write-DeployLog "All updates installed successfully!"
    } else {
        Write-Warning "Some updates failed to install."
    }

    Write-DeployLog "SUCCESS: Windows Update installation done."
    exit 0
} catch {
    Write-DeployLog "Windows Update installation failed: $($_.Exception.Message)" -IsError
    exit 1
}
