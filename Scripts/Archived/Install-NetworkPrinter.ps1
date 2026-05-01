<#
NETWORK PRINTER INSTALLATION SCRIPT (PLACEHOLDER / EXAMPLE)

NOTE: This script was originally written for a Konica Minolta C360i in a specific
environment. It is kept here as a working example and reference implementation.
Feel free to adapt it for your own printer model and network setup.

What needs to change for your environment:
- Driver folder path and INF file name
- Printer model string (used by Add-PrinterDriver)
- Default parameter values ($PrinterName, $PrinterLocation)

What it does:
- Installs printer drivers from a local folder
- Creates a TCP/IP network printer port
- Installs the printer
- Configures default settings

Usage:
.\Install-NetworkPrinter.ps1 -PrinterIP "192.168.1.100" -PrinterName "MyPrinter" -PrinterLocation "Office Floor 1"

Parameters:
  -PrinterIP         IP address of the printer (required)
  -PrinterName       Name for the printer in Windows (required)
  -PrinterLocation   Location description (optional, defaults to empty string)
  -DriverFolder      Path to driver folder (optional, defaults to current directory)

#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$PrinterIP,

    [Parameter(Mandatory = $true)]
    [string]$PrinterName,

    [string]$PrinterLocation = "",

    [string]$DriverFolder = "."
)

# ============================================
# SETTINGS
# ============================================

$DriverName = "KONICA MINOLTA C360iSeriesPCL"    # Official driver name

# Log file location
$LogFile = "C:\ProgramData\Logs\KonicaPrinter.log"

# ============================================
# CHECK: Script must run as Administrator
# ============================================

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host ""
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host ""
    Write-Host "How to fix:" -ForegroundColor Yellow
    Write-Host "1. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor White
    Write-Host "2. Navigate to the script folder: cd C:\Path\To\Script" -ForegroundColor White
    Write-Host "3. Run the script: .\Install-Konica-Minolta_C360i.ps1 -PrinterIP '192.168.1.100' -PrinterName 'MyPrinter'" -ForegroundColor White
    Write-Host ""
    pause
    exit 1
}

# ============================================
# DETECT SYSTEM ARCHITECTURE
# ============================================

$Architecture = $env:PROCESSOR_ARCHITECTURE
if ($Architecture -eq "ARM64") {
    $ArchFolder = "ARM"
} elseif ($Architecture -eq "AMD64" -or $Architecture -eq "x64") {
    $ArchFolder = "Win11-X64"
} else {
    Write-Host "ERROR: Unsupported architecture: $Architecture" -ForegroundColor Red
    Write-Host "Supported architectures: ARM64, AMD64, x64" -ForegroundColor Yellow
    pause
    exit 1
}

# ============================================
# FUNCTION: Write to log file
# ============================================

function Write-PrinterLog {
    param([string]$Message, [string]$Type = "INFO")

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Time] [$Type] $Message"

    # Create log folder if it doesn't exist
    $LogFolder = Split-Path $LogFile -Parent
    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }

    Add-Content -Path $LogFile -Value $LogMessage

    $Color = switch ($Type) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    Write-Host $LogMessage -ForegroundColor $Color
}

# ============================================
# START INSTALLATION
# ============================================

try {
    Write-PrinterLog "========================================"  "INFO"
    Write-PrinterLog "Starting Konica Minolta C360i installation" "INFO"
    Write-PrinterLog "========================================"   "INFO"

    # Get current username
    $Username = (whoami).Split('\')[-1].ToLower()
    Write-PrinterLog "User: $Username"
    Write-PrinterLog "Printer IP: $PrinterIP"
    Write-PrinterLog "Printer name: $PrinterName"
    Write-PrinterLog "System architecture: $Architecture"
    Write-PrinterLog "Selected driver folder: $ArchFolder"

    # Convert relative path to absolute path
    if (-not [System.IO.Path]::IsPathRooted($DriverFolder)) {
        $DriverFolder = Join-Path (Get-Location) $DriverFolder
        $DriverFolder = [System.IO.Path]::GetFullPath($DriverFolder)
    }

    # Append architecture-specific subfolder
    $DriverFolder = Join-Path $DriverFolder $ArchFolder

    Write-PrinterLog "Driver folder: $DriverFolder"

    # Check if driver folder exists
    if (-not (Test-Path $DriverFolder)) {
        throw "Driver folder not found: $DriverFolder"
    }

    # ============================================
    # STEP 1: Install drivers in Windows
    # ============================================

    Write-PrinterLog "Step 1: Installing drivers..." "INFO"

    # Find .inf file in driver folder
    $InfFile = Get-ChildItem -Path $DriverFolder -Filter "*.inf" | Select-Object -First 1

    if (-not $InfFile) {
        throw "No .inf file found in driver folder"
    }

    Write-PrinterLog "INF file found: $($InfFile.Name)"

    # Install driver with PnPUtil
    $PnpUtil = "$env:SystemRoot\System32\pnputil.exe"
    if ($env:PROCESSOR_ARCHITEW6432) {
        $PnpUtil = "$env:SystemRoot\Sysnative\pnputil.exe"  # For 32-bit PowerShell on 64-bit Windows
    }

    Write-PrinterLog "Adding drivers to Windows..."
    & $PnpUtil /add-driver "$($InfFile.FullName)" /install
    Start-Sleep -Seconds 3

    # ============================================
    # STEP 2: Activate printer driver
    # ============================================

    Write-PrinterLog "Step 2: Activating printer driver..." "INFO"

    Add-PrinterDriver -Name $DriverName

    # Check if driver is installed
    $DriverCheck = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
    if (-not $DriverCheck) {
        throw "Driver not found after installation"
    }

    Write-PrinterLog "Driver successfully installed"

    # ============================================
    # STEP 3: Create printer port
    # ============================================

    Write-PrinterLog "Step 3: Creating printer port..." "INFO"

    $PortName = "IP_$($PrinterIP.Replace('.', '_'))"

    # Check if port already exists
    $ExistingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $ExistingPort) {
        Write-PrinterLog "Creating new printer port: $PortName"
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
    } else {
        Write-PrinterLog "Printer port already exists: $PortName"
    }

    # ============================================
    # STEP 4: Install printer
    # ============================================

    Write-PrinterLog "Step 4: Installing printer..." "INFO"

    # Remove old printer if it exists
    $OldPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($OldPrinter) {
        Write-PrinterLog "Removing old printer..."
        Remove-Printer -Name $PrinterName -Confirm:$false
        Start-Sleep -Seconds 2
    }

    # Build Add-Printer parameters
    $PrinterParams = @{
        Name       = $PrinterName
        DriverName = $DriverName
        PortName   = $PortName
        Shared     = $true
        ShareName  = $PrinterName
    }
    if ($PrinterLocation -ne "") {
        $PrinterParams['Location'] = $PrinterLocation
    }

    Add-Printer @PrinterParams

    Write-PrinterLog "Printer added successfully"

    # ============================================
    # STEP 5: Configure printer settings
    # ============================================

    Write-PrinterLog "Step 5: Configuring printer settings..." "INFO"

    Set-PrintConfiguration -PrinterName $PrinterName `
                          -PaperSize A4 `
                          -Color $false `
                          -DuplexingMode OneSided

    Write-PrinterLog "Settings applied (A4, black and white, one-sided)"

    # ============================================
    # STEP 6: Configure authentication
    # ============================================

    Write-PrinterLog "Step 6: Configuring user authentication..." "INFO"

    $RegPath = "HKCU:\Software\KONICA MINOLTA\$DriverName\$PrinterName\Authentication"

    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    Set-ItemProperty -Path $RegPath -Name "UserName" -Value $Username -Force
    Write-PrinterLog "Authentication configured for: $Username"

    # ============================================
    # COMPLETE
    # ============================================

    Write-PrinterLog "========================================" "INFO"
    Write-PrinterLog "Installation completed successfully!" "INFO"
    Write-PrinterLog "========================================" "INFO"

    Write-PrinterLog "Sleeping for 10 seconds to ensure all processes are finalized..." "INFO"
    Start-Sleep -Seconds 10

    exit 0

} catch {
    Write-PrinterLog "========================================" "ERROR"
    Write-PrinterLog "Installation failed: $($_.Exception.Message)" "ERROR"
    Write-PrinterLog "========================================" "ERROR"

    exit 1
}
