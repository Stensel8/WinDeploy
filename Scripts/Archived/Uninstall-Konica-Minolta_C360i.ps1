<#
KONICA MINOLTA C360i PRINTER REMOVAL SCRIPT

This script removes the Konica Minolta C360i printer.

What it does:
- Uninstalls printer drivers
- Removes a network printer port
- Removes the printer
- Cleans up default settings

Usage:
.\Uninstall-Konica-Minolta_C360i.ps1

#>

# ============================================
# SETTINGS (customizable)
# ============================================

$PrinterName = "Konica_Printer_Hal"
$PrinterIP = "172.16.11.97"
$LogFile = "C:\ProgramData\Logs\KonicaPrinter.log"

# ============================================
# CHECK: Script must run as Administrator
# ============================================
# Right-click PowerShell and select "Run as Administrator"
# Then navigate to the script folder and run it

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host ""
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host ""
    Write-Host "How to fix:" -ForegroundColor Yellow
    Write-Host "1. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor White
    Write-Host "2. Navigate to the script folder: cd C:\Path\To\Script" -ForegroundColor White
    Write-Host "3. Run the script: .\Uninstall-Konica-Minolta_C360i.ps1" -ForegroundColor White
    Write-Host ""
    pause
    exit 1
}

# ============================================
# FUNCTION: Write to log file
# ============================================

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    
    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Time] [$Type] $Message"
    
    # Create log folder
    $LogFolder = Split-Path $LogFile -Parent
    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }
    
    # Write to log
    Add-Content -Path $LogFile -Value $LogMessage
    
    # Display on screen
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
    Write-Log "========================================" "INFO"
    Write-Log "Starting printer removal" "INFO"
    Write-Log "========================================" "INFO"
    
    # ============================================
    # STEP 1: Remove printer
    # ============================================
    
    $Printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    
    if ($Printer) {
        Write-Log "Removing printer: $PrinterName"
        Remove-Printer -Name $PrinterName -Confirm:$false
        Write-Log "Printer removed successfully"
    } else {
        Write-Log "Printer not found: $PrinterName" "WARNING"
    }
    
    Start-Sleep -Seconds 2
    
    # ============================================
    # STEP 2: Remove printer port
    # ============================================
    
    $PortName = "IP_$($PrinterIP.Replace('.', '_'))"
    $Port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    
    if ($Port) {
        Write-Log "Removing printer port: $PortName"
        Remove-PrinterPort -Name $PortName -Confirm:$false
        Write-Log "Printer port removed successfully"
    } else {
        Write-Log "Printer port not found: $PortName" "WARNING"
    }
    
    # ============================================
    # COMPLETE
    # ============================================
    
    Write-Log "========================================" "INFO"
    Write-Log "Removal completed successfully" "INFO"
    Write-Log "========================================" "INFO"
    
    Write-Log "Sleeping for 10 seconds to ensure all processes are finalized..." "INFO"
    Start-Sleep -Seconds 10
    
    exit 0

} catch {
    Write-Log "========================================" "ERROR"
    Write-Log "Removal failed: $($_.Exception.Message)" "ERROR"
    Write-Log "========================================" "ERROR"
    
    exit 1
}
