# WinDeploy MSI Installer
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs MSI packages with detailed logging and error handling.

.DESCRIPTION
    Automates MSI installation by extracting properties, installing the package,
    and providing detailed exit code interpretation.

.EXAMPLE
    .\Install-MSI.ps1

.NOTES
    Requires : Admin rights, MSI file
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'Registry.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'Winget.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'Install-MSI.log'
Initialize-Script -RequireAdmin

try {
    Write-Log "=== MSI Installation Started ===" -Level Info

    # ============================================================================ #
    # Auto-detect MSI file
    # ============================================================================ #

    Write-Log "Searching for MSI file in current directory..." -Level Info
    $msiFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.msi' -ErrorAction SilentlyContinue

    if ($msiFiles.Count -eq 0) {
        throw "No MSI files found in $PSScriptRoot"
    } elseif ($msiFiles.Count -gt 1) {
        # Select the first MSI file and log a warning
        Write-Log "Multiple MSI files found, using first one: $($msiFiles[0].Name)" -Level Warning
        $msiFiles | ForEach-Object { Write-Log "  Found: $($_.Name)" -Level Verbose }
    }

    $MSIPath = $msiFiles[0].FullName

    Write-Log "MSI file: $MSIPath" -Level Info

    # ============================================================================ #
    # Extract MSI properties
    # ============================================================================ #

    Write-Log "Extracting MSI properties..." -Level Info

    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember(
            "OpenDatabase",
            "InvokeMethod",
            $null,
            $windowsInstaller,
            @($MSIPath, 0)  # 0 = read-only
        )

        $query = "SELECT Property, Value FROM Property"
        $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, $query)
        $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null

        $msiProperties = @{}
        $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)

        while ($null -ne $record) {
            $property = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
            $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 2)
            $msiProperties[$property] = $value
            $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        }

        $view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null) | Out-Null

        # Log key properties
        if ($msiProperties.ContainsKey('ProductName')) {
            Write-Log "Product Name: $($msiProperties['ProductName'])" -Level Info
        }
        if ($msiProperties.ContainsKey('ProductVersion')) {
            Write-Log "Product Version: $($msiProperties['ProductVersion'])" -Level Info
        }
        if ($msiProperties.ContainsKey('Manufacturer')) {
            Write-Log "Manufacturer: $($msiProperties['Manufacturer'])" -Level Info
        }

    } catch {
        Write-Log "Failed to extract MSI properties: $_" -Level Warning
        $msiProperties = @{}
    }

    # ============================================================================ #
    # Prepare log file path
    # ============================================================================ #

    $msiFileName = [System.IO.Path]::GetFileNameWithoutExtension($MSIPath)
    $logFileName = "${msiFileName}_Install.log"
    $LogPath = Join-Path 'C:\WinDeploy\Logs' $logFileName

    Write-Log "MSI log file: $LogPath" -Level Info

    # ============================================================================ #
    # Build MSI arguments (standard silent install)
    # ============================================================================ #

    $msiArgs = @(
        '/i'
        "`"$MSIPath`""
        '/qn'          # Silent install
        '/norestart'   # Don't restart
        "/L*V `"$LogPath`""  # Verbose logging
    )

    Write-Log "Installation command: msiexec.exe $($msiArgs -join ' ')" -Level Info

    # ============================================================================ #
    # Install MSI
    # ============================================================================ #

    Write-Log "Starting MSI installation..." -Level Info
    $startTime = Get-Date

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    $exitCode = $process.ExitCode

    Write-Log "Installation completed in $([math]::Round($duration, 1)) seconds" -Level Info
    Write-Log "Exit code: $exitCode" -Level Info

    # ============================================================================ #
    # Interpret exit code
    # ============================================================================ #

    $exitCodeInfo = Get-MSIExitCodeDescription -ExitCode $exitCode

    Write-Log "Status: $($exitCodeInfo.Name)" -Level Info
    Write-Log "Description: $($exitCodeInfo.Description)" -Level Info

    # Determine overall status
    $overallStatus = 'Success'
    $finalExitCode = 0

    if ($exitCode -eq 0 -or $exitCode -eq 1707) {
        Write-Log "MSI installation completed successfully" -Level Success
        $overallStatus = 'Success'
        $finalExitCode = 0

        # Record success in Intune registry
        $productName = if ($msiProperties.ContainsKey('ProductName')) {
            $msiProperties['ProductName']
        } else {
            [System.IO.Path]::GetFileNameWithoutExtension($MSIPath)
        }

        $productVersion = if ($msiProperties.ContainsKey('ProductVersion')) {
            $msiProperties['ProductVersion']
        } else {
            '1.0.0'
        }

        Set-IntuneSuccess -AppName $productName -Version $productVersion

    } elseif ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Log "MSI installation succeeded, but a reboot is required" -Level Warning
        $overallStatus = 'Reboot'
        $finalExitCode = 3010

    } else {
        Write-Log "MSI installation failed" -Level Error
        $overallStatus = 'Error'
        $finalExitCode = $exitCode
    }

    Write-Log "=== MSI Installation Complete ===" -Level Success
    Write-Log "Final Status: $overallStatus" -Level Info

    exit $finalExitCode

} catch {
    Write-Log "MSI installation failed with exception: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 9999
} finally {
    Complete-Script
}
