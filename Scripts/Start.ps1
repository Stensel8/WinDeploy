param(
    [string]$VersionTag
)

# Set release tag for downloads
$releaseTag = $null
try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Stensel8/WinDeploy/releases/latest" -ErrorAction SilentlyContinue
    $tag = $latestRelease.tag_name
    if ($tag) {
        $releaseTag = $tag
        $version = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$tag/VERSION" -ErrorAction SilentlyContinue
        $version = $version.Trim()
    }
} catch {
    Write-Host "Failed to fetch latest release. Please run Scripts\Deploy.ps1 manually." -ForegroundColor Red
    exit 1
}
if (!$releaseTag) {
    Write-Host "Failed to fetch latest release tag. Cannot proceed." -ForegroundColor Red
    exit 1
}

# Print header
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                    WinDeploy Deployment" -ForegroundColor Yellow
Write-Host "            Windows Deployment Automation Toolkit" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
if ($version) {
    Write-Host "Version: $version" -ForegroundColor Green
}
Write-Host ""

# Helper: return the pwsh.exe path if installed
function Get-Pwsh7Path {
    $pwshPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    foreach ($path in $pwshPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

# Install PowerShell 7
function Install-Pwsh7 {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Yellow
    
    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements | Out-Null
            Start-Sleep -Seconds 3
            $path = Get-Pwsh7Path
            if ($path) { 
                Write-Host "PowerShell 7 installed successfully via WinGet" -ForegroundColor Green
                return 
            }
        } catch {
            Write-Warning "WinGet installation failed, trying MSI..."
        }
    }
    
    # Fallback to MSI
    try {
        $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
        Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $tempScript -UseBasicParsing
        & powershell.exe -ExecutionPolicy Bypass -File $tempScript -UseMSI -Quiet | Out-Null
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $path = Get-Pwsh7Path
        if ($path) { 
            Write-Host "PowerShell 7 installed successfully via MSI" -ForegroundColor Green
            return 
        }
    } catch {
        Write-Warning "MSI installation failed: $_"
    }
    
    Write-Host "Failed to install PowerShell 7" -ForegroundColor Red
}

# Ensure PowerShell 7 is installed and return its path
function Test-Pwsh7 {
    $path = Get-Pwsh7Path
    if ($path) { return $path }
    
    Install-Pwsh7
    
    # Wait and retry detection
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        $path = Get-Pwsh7Path
        if ($path) { return $path }
    }
    
    return $null
}

# Helper: ensure WinGet present
function Install-WinGet {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    
    Write-Host "Installing WinGet..." -ForegroundColor Yellow
    $temp = [System.IO.Path]::GetTempFileName() + ".ps1"
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1' -OutFile $temp -UseBasicParsing
        $pwsh7 = Get-Pwsh7Path
        if ($pwsh7) {
            & $pwsh7 -ExecutionPolicy Bypass -File $temp | Out-Null
        } else {
            & powershell.exe -ExecutionPolicy Bypass -File $temp | Out-Null
        }
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed to install WinGet: $_"
    }
}

# Check if running as admin and in PowerShell 7
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7

# If not PowerShell 7 or not admin, relaunch
if (-not $isPwsh7 -or -not $isAdmin) {
    $pwshExePath = Test-Pwsh7
    
    if (-not $pwshExePath) {
        Write-Host "Failed to locate or install PowerShell 7. Please install manually." -ForegroundColor Red
        Write-Host "Download from: https://aka.ms/powershell" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Relaunching in PowerShell 7..." -ForegroundColor Yellow
    
    $versionArgs = ""
    if ($VersionTag) { $versionArgs = "-VersionTag '$VersionTag'" }
    
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        # Script run via iex - download to temp
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/Scripts/Start.ps1" -OutFile $scriptPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Failed to download Start.ps1: $_" -ForegroundColor Red
            exit 1
        }
    }
    
    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" $versionArgs"
    
    if ($isAdmin) {
        Start-Process -FilePath $pwshExePath -ArgumentList $argList -Wait -NoNewWindow
    } else {
        Start-Process -FilePath $pwshExePath -ArgumentList $argList -Verb RunAs
    }
    exit
}

# At this point: PowerShell 7 + Admin
Write-Host "Running in PowerShell 7 as Administrator" -ForegroundColor Green
Write-Host ""

# Start logging
$logDir = "C:\WinDeploy\Logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "Start.log"
Start-Transcript -Path $logFile -Append -NoClobber

# Ensure WinGet is installed
Install-WinGet

# Ensure directories exist
$deployDir = "C:\WinDeploy\Download"
if (!(Test-Path $deployDir)) { New-Item -ItemType Directory -Path $deployDir -Force | Out-Null }

# Download Deploy.ps1
$deployPath = Join-Path $deployDir "Deploy.ps1"
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/Scripts/Deploy.ps1" -OutFile $deployPath -UseBasicParsing -ErrorAction Stop
    Write-Host "Downloaded Deploy.ps1 to $deployPath" -ForegroundColor Green
} catch {
    $localDeployPath = Join-Path $PSScriptRoot "Deploy.ps1"
    if (Test-Path $localDeployPath) {
        Copy-Item $localDeployPath $deployPath -Force
        Write-Host "Copied local Deploy.ps1 to $deployPath" -ForegroundColor Green
    } else {
        Write-Host "Cannot download or find Deploy.ps1: $_" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
}

# Launch Deploy.ps1 (we're already in PowerShell 7)
Write-Host "Starting Deploy.ps1..." -ForegroundColor Yellow
Write-Host ""

try {
    & $deployPath
} catch {
    Write-Host "Deploy.ps1 failed: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Stop-Transcript
