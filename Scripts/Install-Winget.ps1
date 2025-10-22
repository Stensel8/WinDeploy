# WinDeploy WinGet Installer
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs and configures Windows Package Manager (WinGet).

.DESCRIPTION
    Ensures WinGet is installed and working properly. Handles dependencies
    (VCLibs, UI.Xaml, VCRedist) and works reliably during OOBE and in 
    environments where modules may not be available.

.EXAMPLE
    .\Install-Winget.ps1

.NOTES
    Requires : Admin rights
#>
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Suppress progress bar for faster downloads

# ============================================================================
# BOOTSTRAP LOGGING (before modules are available)
# ============================================================================

$script:LogDirectory = 'C:\WinDeploy\Logs'
$script:LogFile = Join-Path $script:LogDirectory 'Install-Winget.log'

if (!(Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-BootstrapLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage -Force

    # Also write to console with colors
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

function Test-SystemAccount {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User -match "S-1-5-18"
}

function Get-WingetDownloadUrl {
    param([Parameter(Mandatory)][string]$Match)

    try {
        $uri = 'https://api.github.com/repos/microsoft/winget-cli/releases'
        $releases = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop -UseBasicParsing

        foreach ($release in $releases) {
            if ($release.name -match 'preview' -or $release.prerelease) { continue }
            $asset = $release.assets | Where-Object name -Match $Match
            if ($asset) { return $asset.browser_download_url }
        }

        # Fallback to latest release
        $latest = $releases | Select-Object -First 1
        return ($latest.assets | Where-Object name -Match $Match).browser_download_url
    } catch {
        Write-BootstrapLog "Failed to get download URL: $_" -Level ERROR
        throw
    }
}

function Get-ManifestVersion {
    param([Parameter(Mandatory)][string]$Lib_Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Lib_Path)
    $entry = $zip.Entries | Where-Object { $_.FullName -eq "AppxManifest.xml" }

    if ($entry) {
        $stream = $entry.Open()
        $reader = New-Object System.IO.StreamReader($stream)
        [xml]$xml = $reader.ReadToEnd()
        $reader.Close()
        $zip.Dispose()
        return $xml.Package.Identity.Version
    } else {
        $zip.Dispose()
        throw "AppxManifest.xml not found in $Lib_Path"
    }
}

function Get-InstalledLibVersion {
    param([Parameter(Mandatory)][string]$Lib_Name)

    $pkg = Get-AppxPackage -Name "*$Lib_Name*" -ErrorAction SilentlyContinue |
           Sort-Object Version -Descending | Select-Object -First 1

    if ($pkg) {
        return $pkg.Version
    }
    return $null
}

function Install-LibIfRequired {
    param(
        [Parameter(Mandatory)][string]$Lib_Name,
        [Parameter(Mandatory)][string]$Lib_Path,
        [switch]$RunAsSystem
    )

    $installedVersion = Get-InstalledLibVersion -Lib_Name $Lib_Name
    $downloadedVersion = Get-ManifestVersion -Lib_Path $Lib_Path

    if ($installedVersion -and ([version]$downloadedVersion -le [version]$installedVersion)) {
        Write-BootstrapLog "  $Lib_Name version $installedVersion is up-to-date" -Level INFO
        return
    }

    Write-BootstrapLog "  Installing $Lib_Name version $downloadedVersion..." -Level INFO

    if ($RunAsSystem) {
        Add-AppxProvisionedPackage -Online -SkipLicense -PackagePath $Lib_Path | Out-Null
    } else {
        Add-AppxPackage -Path $Lib_Path | Out-Null
    }

    Write-BootstrapLog "  $Lib_Name installed successfully" -Level SUCCESS
}

function Resolve-InstallError {
    param($ErrorRecord)

    $errorMessage = $ErrorRecord.Exception.Message

    # Handle common installation errors (inspired by asheroto/winget-install)
    if ($errorMessage -match '0x80073D06') {
        Write-BootstrapLog "Higher version already installed - continuing" -Level WARNING
        return $false # Don't rethrow
    } elseif ($errorMessage -match '0x80073CF0') {
        Write-BootstrapLog "Same version already installed - continuing" -Level WARNING
        return $false # Don't rethrow
    } elseif ($errorMessage -match '0x80073D02') {
        Write-BootstrapLog "Resources in use - close all PowerShell/Terminal windows and try again" -Level ERROR
        return $true # Rethrow
    } elseif ($errorMessage -match '0x80073CF3') {
        Write-BootstrapLog "Prerequisite problem - try running the script again" -Level ERROR
        return $true # Rethrow
    } elseif ($errorMessage -match '0x80073CF9') {
        Write-BootstrapLog "Registration failed (common with SYSTEM account)" -Level WARNING
        return $false # Don't rethrow
    } elseif ($errorMessage -match 'Unable to connect to the remote server') {
        Write-BootstrapLog "Cannot connect to Internet - check network connection" -Level ERROR
        return $true # Rethrow
    } else {
        return $true # Rethrow unknown errors
    }
}

function Test-VCRedistInstalled {
    $is64Os = [Environment]::Is64BitOperatingSystem
    $is64Process = [Environment]::Is64BitProcess

    $regPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\$(if ($is64Os -and $is64Process) { 'WOW6432Node\' })Microsoft\VisualStudio\14.0\VC\Runtimes\X$(if ($is64Os) { '64' } else { '86' })"

    $registryExists = Test-Path $regPath
    $majorVersion = if ($registryExists) { (Get-ItemProperty -Path $regPath -Name 'Major' -ErrorAction SilentlyContinue).Major } else { 0 }
    $dllPath = Join-Path $env:WINDIR 'system32\concrt140.dll'

    return ($registryExists -and $majorVersion -eq 14 -and (Test-Path $dllPath))
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

try {
    Write-BootstrapLog "========================================" -Level INFO
    Write-BootstrapLog "  WinGet Installation Script v7.0.0" -Level INFO
    Write-BootstrapLog "  Inspired by asheroto/winget-install" -Level INFO
    Write-BootstrapLog "========================================" -Level INFO
    Write-BootstrapLog "" -Level INFO

    # Check admin privileges
    if (-not (Test-AdminPrivilege)) {
        Write-BootstrapLog "ERROR: Administrator privileges required" -Level ERROR
        exit 1
    }

    # Detect if running as SYSTEM
    $runAsSystem = Test-SystemAccount
    if ($runAsSystem) {
        Write-BootstrapLog "Running as SYSTEM account" -Level INFO
    }

    # Check if WinGet is already available
    Write-BootstrapLog "Checking if WinGet is already installed..." -Level INFO
    $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCheck) {
        $version = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-BootstrapLog "WinGet is already installed ($version)" -Level SUCCESS
            Write-BootstrapLog "========================================" -Level INFO
            exit 0
        }
    }

    # Get OS architecture
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') { $arch = 'x64' }
    elseif ($arch -eq 'ARM64') { $arch = 'arm64' }
    else { $arch = 'x86' }

    Write-BootstrapLog "System architecture: $arch" -Level INFO

    # ============================================================================
    # Install Dependencies
    # ============================================================================

    Write-BootstrapLog "" -Level INFO
    Write-BootstrapLog "Installing WinGet dependencies..." -Level INFO

    try {
        # Download dependencies package
        $depsUrl = Get-WingetDownloadUrl -Match 'DesktopAppInstaller_Dependencies.zip'
        $depsPath = Join-Path $env:TEMP 'WinGet_Dependencies.zip'

        Write-BootstrapLog "Downloading dependencies from GitHub..." -Level INFO
        Invoke-WebRequest -Uri $depsUrl -OutFile $depsPath -UseBasicParsing

        # Extract and install matching architecture dependencies
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($depsPath)
        $matchingEntries = $zip.Entries | Where-Object { $_.FullName -match ".*$arch.*\.appx$" }

        foreach ($entry in $matchingEntries) {
            $destPath = Join-Path $env:TEMP $entry.Name
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)

            # Extract package name from manifest
            $libName = (Get-ManifestVersion $destPath).Split('.')[0..2] -join '.'

            Write-BootstrapLog "Installing dependency: $($entry.Name)" -Level INFO
            Install-LibIfRequired -Lib_Name $libName -Lib_Path $destPath -RunAsSystem:$runAsSystem

            Remove-Item $destPath -Force -ErrorAction SilentlyContinue
        }

        $zip.Dispose()
        Remove-Item $depsPath -Force -ErrorAction SilentlyContinue

    } catch {
        $shouldRethrow = Resolve-InstallError $_
        if ($shouldRethrow) { throw }
    }

    # ============================================================================
    # Install Visual C++ Redistributable (if needed)
    # ============================================================================

    if (-not (Test-VCRedistInstalled)) {
        Write-BootstrapLog "" -Level INFO
        Write-BootstrapLog "Installing Visual C++ Redistributable..." -Level INFO

        try {
            $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.$arch.exe"
            $vcRedistPath = Join-Path $env:TEMP "vc_redist_$arch.exe"

            Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
            $process = Start-Process -FilePath $vcRedistPath -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru

            if ($process.ExitCode -in @(0, 1638, 3010)) {
                Write-BootstrapLog "VCRedist installed successfully (exit code: $($process.ExitCode))" -Level SUCCESS
            } else {
                Write-BootstrapLog "VCRedist exit code: $($process.ExitCode)" -Level WARNING
            }

            Remove-Item $vcRedistPath -Force -ErrorAction SilentlyContinue
        } catch {
            Write-BootstrapLog "VCRedist installation failed: $_" -Level WARNING
        }
    } else {
        Write-BootstrapLog "Visual C++ Redistributable already installed" -Level INFO
    }

    # ============================================================================
    # Install WinGet Package
    # ============================================================================

    Write-BootstrapLog "" -Level INFO
    Write-BootstrapLog "Installing WinGet package..." -Level INFO

    try {
        # Method 1: Try Microsoft.WinGet.Client module (fastest for modern systems)
        Write-BootstrapLog "Attempting installation via Microsoft.WinGet.Client module..." -Level INFO

        # Install NuGet if needed
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -ForceBootstrap | Out-Null
        }

        # Install WinGet Client module
        if (-not (Get-Module -Name Microsoft.WinGet.Client -ListAvailable)) {
            Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null
        }

        # Repair WinGet using the module
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null

        Write-BootstrapLog "WinGet installed via Microsoft.WinGet.Client" -Level SUCCESS

    } catch {
        $shouldRethrow = Resolve-InstallError $_
        if ($shouldRethrow) {
            # Method 2: Fallback to manual installation
            Write-BootstrapLog "Microsoft.WinGet.Client method failed, trying manual installation..." -Level WARNING

            try {
                # Download license
                $licenseUrl = Get-WingetDownloadUrl -Match 'License1.xml'
                $licensePath = Join-Path $env:TEMP 'winget_license.xml'
                Invoke-WebRequest -Uri $licenseUrl -OutFile $licensePath -UseBasicParsing

                # Download WinGet
                $wingetUrl = Get-WingetDownloadUrl -Match 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
                $wingetPath = Join-Path $env:TEMP 'winget.msixbundle'
                Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath -UseBasicParsing

                Write-BootstrapLog "Installing WinGet package..." -Level INFO
                Add-AppxProvisionedPackage -Online -PackagePath $wingetPath -LicensePath $licensePath | Out-Null

                # Cleanup
                Remove-Item $wingetPath, $licensePath -Force -ErrorAction SilentlyContinue

                Write-BootstrapLog "WinGet installed via manual installation" -Level SUCCESS

                } catch {
                $shouldRethrow2 = Resolve-InstallError $_
                if ($shouldRethrow2) { throw }
            }
        }
    }

    # ============================================================================
    # Register WinGet
    # ============================================================================

    Write-BootstrapLog "" -Level INFO
    Write-BootstrapLog "Registering WinGet..." -Level INFO

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
        Write-BootstrapLog "WinGet registered successfully" -Level SUCCESS
    } catch {
        $shouldRethrow = Resolve-InstallError $_
        if ($shouldRethrow) {
            Write-BootstrapLog "WinGet registration failed (may still work)" -Level WARNING
        }
    }

    # ============================================================================
    # Verify Installation
    # ============================================================================

    Write-BootstrapLog "" -Level INFO
    Write-BootstrapLog "Verifying WinGet installation..." -Level INFO
    Start-Sleep -Seconds 3

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    $wingetCheck = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCheck) {
        $version = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-BootstrapLog "" -Level INFO
            Write-BootstrapLog "========================================" -Level SUCCESS
            Write-BootstrapLog "Installation Complete!" -Level SUCCESS
            Write-BootstrapLog "  WinGet Version: $version" -Level SUCCESS
            Write-BootstrapLog "========================================" -Level SUCCESS
            exit 0
        }
    }

    Write-BootstrapLog "WinGet installed but not immediately available" -Level WARNING
    Write-BootstrapLog "Try waiting 1 minute or restarting your computer" -Level WARNING
    Write-BootstrapLog "========================================" -Level WARNING
    exit 0

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
