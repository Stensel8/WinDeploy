# WinDeploy PowerShell 7 Installer
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs PowerShell 7 via Windows Package Manager (WinGet).

.DESCRIPTION
    Self-contained installer for PowerShell 7. Ensures WinGet is available
    and verifies installation succeeded.

.EXAMPLE
    .\Install-PowerShell7.ps1

.NOTES
    Requires : PowerShell 5.1+, Admin rights
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ============================================================================
# BOOTSTRAP LOGGING (before modules are available)
# ============================================================================

$script:LogDirectory = 'C:\WinDeploy\Logs'
$script:LogFile = Join-Path $script:LogDirectory 'Install-PowerShell7.log'

if (!(Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-BootstrapLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage -Force

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'INFO' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# ============================================================================
# BOOTSTRAP HELPER FUNCTIONS
# ============================================================================

function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PowerShell7Installed {
    $possiblePaths = @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $true
        }
    }

    return $false
}

function Install-WinGetIfNeeded {
    # Check if WinGet is available
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $testRun = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-BootstrapLog "WinGet is available: $testRun" -Level INFO
            return $winget.Source
        }
    }

    Write-BootstrapLog "WinGet not available - installing..." -Level WARNING

    # Call Install-Winget.ps1 if it exists
    $installWingetPath = Join-Path $PSScriptRoot 'Install-Winget.ps1'
    if (Test-Path $installWingetPath) {
        Write-BootstrapLog "Running Install-Winget.ps1..." -Level INFO
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installWingetPath
        if ($LASTEXITCODE -eq 0) {
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 2

            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if ($winget) {
                return $winget.Source
            }
        }
    }

    throw "Unable to install or locate WinGet"
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

try {
    Write-BootstrapLog "========================================" -Level INFO
    Write-BootstrapLog "  PowerShell 7 Installation Script v2.0.0" -Level INFO
    Write-BootstrapLog "========================================" -Level INFO
    Write-BootstrapLog "Current PowerShell Version: $($PSVersionTable.PSVersion)" -Level INFO
    Write-BootstrapLog "" -Level INFO

    # Check admin privileges
    if (-not (Test-AdminPrivilege)) {
        Write-BootstrapLog "ERROR: Administrator privileges required" -Level ERROR
        exit 1
    }

    # Check if PowerShell 7 is already installed
    if (Test-PowerShell7Installed) {
        Write-BootstrapLog "PowerShell 7 is already installed" -Level SUCCESS
        Write-BootstrapLog "========================================" -Level INFO
        exit 0
    }

    # Ensure WinGet is available
    Write-BootstrapLog "Ensuring WinGet is available..." -Level INFO
    $wingetPath = Install-WinGetIfNeeded

    # Install PowerShell 7 via WinGet
    Write-BootstrapLog "" -Level INFO
    Write-BootstrapLog "Installing PowerShell 7 via WinGet..." -Level INFO

    $arguments = @(
        'install',
        '--id', 'Microsoft.PowerShell',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    $process = Start-Process $wingetPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

    # WinGet exit codes:
    # 0 = Success
    # -1978335189 = Already installed (up-to-date)
    # -1978335135 = Package already installed
    $successCodes = @(0, -1978335189, -1978335135)

    if ($process.ExitCode -in $successCodes) {
        Write-BootstrapLog "PowerShell 7 installation command completed (exit code: $($process.ExitCode))" -Level SUCCESS

        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        Start-Sleep -Seconds 3

        # Verify installation
        if (Test-PowerShell7Installed) {
            Write-BootstrapLog "" -Level INFO
            Write-BootstrapLog "========================================" -Level SUCCESS
            Write-BootstrapLog "Installation Complete!" -Level SUCCESS
            Write-BootstrapLog "To use PowerShell 7, run: pwsh" -Level INFO
            Write-BootstrapLog "========================================" -Level SUCCESS
            exit 0
        } else {
            Write-BootstrapLog "" -Level WARNING
            Write-BootstrapLog "Installation completed but PowerShell 7 not detected" -Level WARNING
            Write-BootstrapLog "Restart may be required" -Level WARNING
            Write-BootstrapLog "========================================" -Level WARNING
            exit 0
        }
    } else {
        Write-BootstrapLog "Installation failed with exit code: $($process.ExitCode)" -Level ERROR
        exit 1
    }

} catch {
    Write-BootstrapLog "" -Level ERROR
    Write-BootstrapLog "========================================" -Level ERROR
    Write-BootstrapLog "Installation Failed!" -Level ERROR
    Write-BootstrapLog "  Error: $($_.Exception.Message)" -Level ERROR
    Write-BootstrapLog "========================================" -Level ERROR

    if ($_.ScriptStackTrace) {
        Write-BootstrapLog "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }

    exit 1
}
