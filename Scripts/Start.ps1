param(
    [string]$VersionTag,
    [switch]$Relaunched
)

# Fetch latest release with retry logic
function Get-LatestRelease {
    param(
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Stensel8/WinDeploy/releases/latest" -ErrorAction Stop
            if ($latestRelease.tag_name) {
                return $latestRelease.tag_name
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "Failed to fetch latest release (attempt $attempt/$MaxRetries): $errorMsg"

            if ($attempt -lt $MaxRetries) {
                if ($errorMsg -match "403|401") {
                    Write-Host "Possible issue: GitHub API rate limit or authentication required" -ForegroundColor Yellow
                } elseif ($errorMsg -match "404") {
                    Write-Host "Possible issue: No releases found in repository" -ForegroundColor Yellow
                }
                Write-Host "Waiting $RetryDelay seconds before retry..." -ForegroundColor Cyan
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }
    return $null
}

# Get release tag — use $VersionTag if supplied, otherwise fetch latest
if ($VersionTag) {
    $releaseTag = $VersionTag
} else {
    $releaseTag = Get-LatestRelease
}
if (!$releaseTag) {
    Write-Host "ERROR: Failed to fetch latest release from GitHub." -ForegroundColor Red
    Write-Host "Releases are required for deployment. Please check:" -ForegroundColor Yellow
    Write-Host "  1. Your internet connection" -ForegroundColor Yellow
    Write-Host "  2. GitHub API accessibility" -ForegroundColor Yellow
    Write-Host "  3. Repository has published releases: github.com/Stensel8/WinDeploy/releases" -ForegroundColor Yellow
    exit 1
}

# Read version
$version = $null
try {
    $version = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/VERSION" -ErrorAction SilentlyContinue
    $version = $version.Trim()
} catch {
    Write-Warning "Failed to fetch version information."
}

# Clear screen if relaunched
if ($Relaunched) {
    Clear-Host
}

# Print header
Write-Host "============================================================" -ForegroundColor Cyan
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

# Refresh environment PATH without restarting
function Update-EnvironmentPath {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess("Environment PATH", "Update")) {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
}

# Install PowerShell 7 with multiple fallback methods
function Install-Pwsh7 {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Yellow

    # Method 1: Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Attempting installation via WinGet..." -ForegroundColor Cyan
        try {
            & winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements 2>&1
            Start-Sleep -Seconds 5
            Update-EnvironmentPath
            $path = Get-Pwsh7Path
            if ($path) {
                Write-Host "PowerShell 7 installed successfully via WinGet" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Warning "WinGet installation failed: $_"
        }
    }

    # Method 2: MSI installer from Microsoft
    Write-Host "Attempting installation via MSI..." -ForegroundColor Cyan
    try {
        $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
        Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $tempScript -UseBasicParsing
        & powershell.exe -ExecutionPolicy Bypass -File $tempScript -UseMSI -Quiet 2>&1 | Out-Null
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Update-EnvironmentPath
        $path = Get-Pwsh7Path
        if ($path) {
            Write-Host "PowerShell 7 installed successfully via MSI" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "MSI installation failed: $_"
    }

    # Method 3: Direct MSI download using latest release from GitHub API
    Write-Host "Attempting direct MSI download..." -ForegroundColor Cyan
    try {
        $psRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -ErrorAction Stop
        $psVersion = $psRelease.tag_name.TrimStart('v')
        $msiAsset = $psRelease.assets | Where-Object { $_.name -like "*win-x64.msi" } | Select-Object -First 1
        if (-not $msiAsset) { throw "MSI asset not found in latest PowerShell release" }
        $msiPath = Join-Path $env:TEMP "PowerShell-7.msi"
        Invoke-WebRequest -Uri $msiAsset.browser_download_url -OutFile $msiPath -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -NoNewWindow
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Update-EnvironmentPath
        $path = Get-Pwsh7Path
        if ($path) {
            Write-Host "PowerShell $psVersion installed successfully via direct MSI" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "Direct MSI installation failed: $_"
    }

    Write-Host "Failed to install PowerShell 7 using all available methods" -ForegroundColor Red
    return $false
}

# Ensure PowerShell 7 is installed and return its path
function Test-Pwsh7 {
    $path = Get-Pwsh7Path
    if ($path) { return $path }

    # Refresh PATH in case it was just installed
    Update-EnvironmentPath
    $path = Get-Pwsh7Path
    if ($path) { return $path }

    # Need to install
    $success = Install-Pwsh7
    if (-not $success) { return $null }

    # Wait and retry detection with PATH refresh
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        Update-EnvironmentPath
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
            & $pwsh7 -ExecutionPolicy Bypass -File $temp 2>&1 | Out-Null
        } else {
            & powershell.exe -ExecutionPolicy Bypass -File $temp 2>&1 | Out-Null
        }
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        Update-EnvironmentPath
    } catch {
        Write-Warning "Failed to install WinGet: $_"
    }
}

# Check if running as admin and in PowerShell 7
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7

# If not admin, elevate FIRST before doing anything else
if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow

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

    # Use current PowerShell to elevate
    $currentPwsh = if ($isPwsh7) { "pwsh" } else { "powershell" }
    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" $versionArgs"

    Start-Process -FilePath $currentPwsh -ArgumentList $argList -Verb RunAs
    exit
}

# NOW we're admin - check if we need PowerShell 7
if (-not $isPwsh7) {
    Write-Host "PowerShell 7 not detected. Installing..." -ForegroundColor Yellow

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

    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" $versionArgs -Relaunched"
    Start-Process -FilePath $pwshExePath -ArgumentList $argList -Wait -NoNewWindow
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

# Download Deploy.ps1 with retry logic
$deployPath = Join-Path $deployDir "Deploy.ps1"
$maxRetries = 3
$retryDelay = 5
$downloadSuccess = $false

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        Write-Host "Downloading Deploy.ps1 (Attempt $attempt of $maxRetries)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Stensel8/WinDeploy/$releaseTag/Scripts/Deploy.ps1" -OutFile $deployPath -UseBasicParsing -ErrorAction Stop
        Write-Host "Downloaded Deploy.ps1 to $deployPath" -ForegroundColor Green
        $downloadSuccess = $true
        break
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Download attempt $attempt failed: $errorMsg"

        if ($attempt -lt $maxRetries) {
            # Diagnose the issue
            if ($errorMsg -match "403|401") {
                Write-Host "Possible issue: GitHub API rate limit or authentication required" -ForegroundColor Yellow
            } elseif ($errorMsg -match "404") {
                Write-Host "Possible issue: Deploy.ps1 not found at release $releaseTag" -ForegroundColor Yellow
            } elseif ($errorMsg -match "timeout|timed out") {
                Write-Host "Possible issue: Network timeout or slow connection" -ForegroundColor Yellow
            } else {
                Write-Host "Possible issue: Network connectivity or GitHub service unavailable" -ForegroundColor Yellow
            }

            Write-Host "Waiting $retryDelay seconds before retry..." -ForegroundColor Cyan
            Start-Sleep -Seconds $retryDelay
        }
    }
}

# If download failed after all retries, try local copy
if (-not $downloadSuccess) {
    Write-Warning "Failed to download Deploy.ps1 after $maxRetries attempts"
    $localDeployPath = Join-Path $PSScriptRoot "Deploy.ps1"
    if (Test-Path $localDeployPath) {
        Copy-Item $localDeployPath $deployPath -Force
        Write-Host "Copied local Deploy.ps1 to $deployPath" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Cannot download or find Deploy.ps1" -ForegroundColor Red
        Write-Host "Please check:" -ForegroundColor Yellow
        Write-Host "  1. Your internet connection" -ForegroundColor Yellow
        Write-Host "  2. GitHub.com accessibility" -ForegroundColor Yellow
        Write-Host "  3. Release $releaseTag contains Scripts/Deploy.ps1" -ForegroundColor Yellow
        Stop-Transcript
        Read-Host "Press Enter to exit"
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
