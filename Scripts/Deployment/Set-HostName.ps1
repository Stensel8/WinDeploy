# ============================================================================
# Set-Hostname.ps1
# Sets hostname to PC-XXXXX (last 5 serial digits).
# Compatible: Datto RMM | User/Admin context (post-install).
# ============================================================================

#requires -Version 5.1
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

Write-Output "Setting hostname."

try {
    Write-DeployLog "=== Hostname Setup ==="

    $Serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber -replace '[^A-Z0-9]', ''
    $LastFive = $Serial.Substring($Serial.Length - 5).ToUpper()
    $Hostname = "PC-$LastFive"

    $Current = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
    Write-DeployLog "Current: $Current | New: $Hostname"
    Write-Output "Current hostname: $Current | Target: $Hostname"

    if ($Current -eq $Hostname) {
        Write-DeployLog "Already correct."
        Write-Output "Hostname already $Hostname."
        exit 0
    }

    Rename-Computer -NewName $Hostname -Restart:$false -Force -ErrorAction SilentlyContinue
    if ($?) {
        Write-DeployLog "Set successfully - reboot needed."
        Write-Output "Hostname set to $Hostname - reboot required."
    } else {
        Write-DeployLog "Set failed - continuing." -IsError:$true
        Write-Error "Hostname change failed."
    }

    Write-DeployLog "SUCCESS: Hostname done."
    Write-Output "Hostname setup completed."
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError:$true
    Write-Error "Hostname partial - continuing."
    exit 0
}
