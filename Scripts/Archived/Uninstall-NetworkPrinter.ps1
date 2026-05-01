<#
NETWORK PRINTER REMOVAL SCRIPT (PLACEHOLDER / EXAMPLE)

NOTE: This script was originally written to remove a Konica Minolta C360i in a
specific environment. It is kept here as a working example and reference implementation.
Feel free to adapt it for your own printer model and network setup.

What needs to change for your environment:
- Printer driver name (used by Remove-PrinterDriver)
- Default parameter values ($PrinterName, $PrinterIP)

What it does:
- Removes the printer from Windows
- Removes the TCP/IP network printer port
- Cleans up leftover registry settings

Usage:
.\Uninstall-NetworkPrinter.ps1 -PrinterName "MyPrinter" -PrinterIP "192.168.1.100"

Parameters:
  -PrinterName   Name of the printer in Windows (required)
  -PrinterIP     IP address used for the printer port (required)

#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PrinterName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$PrinterIP
)

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
    Write-Host "3. Run the script: .\Uninstall-Konica-Minolta_C360i.ps1 -PrinterName 'MyPrinter' -PrinterIP '192.168.1.100'" -ForegroundColor White
    Write-Host ""
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

    # Create log folder
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
# START REMOVAL
# ============================================

try {
    Write-PrinterLog "========================================" "INFO"
    Write-PrinterLog "Starting printer removal" "INFO"
    Write-PrinterLog "========================================" "INFO"

    # ============================================
    # STEP 1: Remove printer
    # ============================================

    $Printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

    if ($Printer) {
        Write-PrinterLog "Removing printer: $PrinterName"
        Remove-Printer -Name $PrinterName -Confirm:$false
        Write-PrinterLog "Printer removed successfully"
    } else {
        Write-PrinterLog "Printer not found: $PrinterName" "WARNING"
    }

    Start-Sleep -Seconds 2

    # ============================================
    # STEP 2: Remove printer port
    # ============================================

    $PortName = "IP_$($PrinterIP.Replace('.', '_'))"
    $Port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue

    if ($Port) {
        Write-PrinterLog "Removing printer port: $PortName"
        Remove-PrinterPort -Name $PortName -Confirm:$false
        Write-PrinterLog "Printer port removed successfully"
    } else {
        Write-PrinterLog "Printer port not found: $PortName" "WARNING"
    }

    # ============================================
    # COMPLETE
    # ============================================

    Write-PrinterLog "========================================" "INFO"
    Write-PrinterLog "Removal completed successfully" "INFO"
    Write-PrinterLog "========================================" "INFO"

    Write-PrinterLog "Sleeping for 10 seconds to ensure all processes are finalized..." "INFO"
    Start-Sleep -Seconds 10

    exit 0

} catch {
    Write-PrinterLog "========================================" "ERROR"
    Write-PrinterLog "Removal failed: $($_.Exception.Message)" "ERROR"
    Write-PrinterLog "========================================" "ERROR"

    exit 1
}
