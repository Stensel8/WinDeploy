# ============================================================================
# Driver Management Module
# Part of the WinDeploy Automation Toolkit
# ============================================================================

<#
.SYNOPSIS
    Provides functions for importing and exporting Windows drivers using pnputil.exe

.DESCRIPTION
    This module contains functions to install drivers from INF files and export
    third-party drivers from the system. All functions include proper error handling
    and logging.

.NOTES
    Requires: Admin rights, Windows 10/11, pnputil.exe
    Author: Sten Tijhuis
    Project      : WinDeploy
#>

# ============================================================================
# DRIVER IMPORT FUNCTIONS
# ============================================================================

function Install-DriversFromPath {
    <#
    .SYNOPSIS
        Installs all driver INF files found recursively in the specified path.

    .PARAMETER Path
        The folder path containing driver INF files to install.

    .PARAMETER Recurse
        Whether to search recursively in subdirectories. Default is $true.

    .OUTPUTS
        PSCustomObject with properties: Total, Installed, Failed, Errors

    .EXAMPLE
        $result = Install-DriversFromPath -Path "C:\drivers\intel"
        Write-Host "Installed $($result.Installed) drivers, $($result.Failed) failed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [bool]$Recurse = $true
    )

    if (-not (Test-Path $Path)) {
        throw "Driver folder '$Path' does not exist."
    }

    Write-Log "Scanning for driver INF files in: $Path" -Level Info
    $driverFiles = Get-ChildItem -Path $Path -Recurse:$Recurse -Filter *.inf

    if ($driverFiles.Count -eq 0) {
        Write-Log "No driver INF files found in $Path" -Level Warning
        return [PSCustomObject]@{
            Total = 0
            Installed = 0
            Failed = 0
            Errors = @()
        }
    }

    Write-Log "Found $($driverFiles.Count) driver INF file(s)" -Level Info

    $installedCount = 0
    $failedCount = 0
    $errors = @()

    foreach ($driver in $driverFiles) {
        Write-Log "Installing driver: $($driver.FullName)" -Level Info
        try {
            $output = pnputil /add-driver $driver.FullName /install 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Log "✓ Installed driver $($driver.Name) successfully" -Level Success
                $installedCount++
            } else {
                $errorMsg = "Failed to install driver $($driver.Name) (exit code: $exitCode)"
                Write-Log "✗ $errorMsg" -Level Warning
                Write-Log "  Output: $output" -Level Verbose
                $failedCount++
                $errors += [PSCustomObject]@{
                    Driver = $driver.Name
                    Path = $driver.FullName
                    Error = $errorMsg
                    Output = $output
                    ExitCode = $exitCode
                }
            }
        }
        catch {
            $errorMsg = "Exception during install of $($driver.Name): $($_.Exception.Message)"
            Write-Log "✗ $errorMsg" -Level Error
            $failedCount++
            $errors += [PSCustomObject]@{
                Driver = $driver.Name
                Path = $driver.FullName
                Error = $errorMsg
                Output = $null
                ExitCode = -1
            }
        }
    }

    # Summary
    Write-Log "" -Level Info
    Write-Log "Installation Summary:" -Level Info
    Write-Log "  Total drivers found: $($driverFiles.Count)" -Level Info
    Write-Log "  Successfully installed: $installedCount" -Level $(if ($installedCount -gt 0) { 'Success' } else { 'Info' })
    Write-Log "  Failed: $failedCount" -Level $(if ($failedCount -gt 0) { 'Warning' } else { 'Info' })

    return [PSCustomObject]@{
        Total = $driverFiles.Count
        Installed = $installedCount
        Failed = $failedCount
        Errors = $errors
    }
}

function Install-SingleDriver {
    <#
    .SYNOPSIS
        Installs a single driver INF file.

    .PARAMETER InfPath
        Path to the driver INF file to install.

    .OUTPUTS
        PSCustomObject with properties: Success, ExitCode, Output

    .EXAMPLE
        $result = Install-SingleDriver -InfPath "C:\drivers\driver.inf"
        if ($result.Success) { Write-Host "Driver installed successfully" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InfPath
    )

    if (-not (Test-Path $InfPath)) {
        throw "Driver INF file '$InfPath' does not exist."
    }

    $driverName = [System.IO.Path]::GetFileName($InfPath)
    Write-Log "Installing driver: $driverName" -Level Info

    try {
        $output = pnputil /add-driver $InfPath /install 2>&1
        $exitCode = $LASTEXITCODE

        $success = $exitCode -eq 0
        if ($success) {
            Write-Log "✓ Installed driver $driverName successfully" -Level Success
        } else {
            Write-Log "✗ Failed to install driver $driverName (exit code: $exitCode)" -Level Warning
            Write-Log "  Output: $output" -Level Verbose
        }

        return [PSCustomObject]@{
            Success = $success
            ExitCode = $exitCode
            Output = $output
        }
    }
    catch {
        $errorMsg = "Exception during install of $driverName`: $($_.Exception.Message)"
        Write-Log "✗ $errorMsg" -Level Error
        return [PSCustomObject]@{
            Success = $false
            ExitCode = -1
            Output = $errorMsg
        }
    }
}

# ============================================================================
# DRIVER EXPORT FUNCTIONS
# ============================================================================

function Export-DriverPackage {
    <#
    .SYNOPSIS
        Exports all third-party drivers from the system to the specified path.

    .PARAMETER Path
        The folder path where drivers will be exported.

    .PARAMETER CreateDirectory
        Whether to create the directory if it doesn't exist. Default is $true.

    .OUTPUTS
        PSCustomObject with properties: Success, ExitCode, Output, Duration

    .EXAMPLE
    $result = Export-DriverPackage -Path "C:\drivers\backup"
        if ($result.Success) {
            Write-Host "Drivers exported in $($result.Duration) seconds"
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [bool]$CreateDirectory = $true
    )

    if ($CreateDirectory -and -not (Test-Path $Path)) {
        Write-Log "Creating directory $Path..." -Level Info
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $Path)) {
        throw "Export path '$Path' does not exist and CreateDirectory is false."
    }

    Write-Log "Exporting drivers to $Path. This may take some time..." -Level Info

    $startTime = Get-Date
    try {
        $exportResult = pnputil /export-driver * $Path 2>&1
        $exitCode = $LASTEXITCODE
        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Log the output
        Write-Log "pnputil output:" -Level Info
        $exportResult | ForEach-Object { Write-Log "  $_" -Level Info }

        $success = $exitCode -eq 0
        if ($success) {
            Write-Log "✓ Drivers exported successfully ($([math]::Round($duration, 1))s)" -Level Success
        } else {
            Write-Log "✗ Some errors occurred during export (exit code: $exitCode, $([math]::Round($duration, 1))s)" -Level Warning
        }

        return [PSCustomObject]@{
            Success = $success
            ExitCode = $exitCode
            Output = $exportResult
            Duration = [math]::Round($duration, 1)
        }
    }
    catch {
        $errorMsg = "Export failed with exception: $($_.Exception.Message)"
        Write-Log "✗ $errorMsg" -Level Error
        return [PSCustomObject]@{
            Success = $false
            ExitCode = -1
            Output = $errorMsg
            Duration = ((Get-Date) - $startTime).TotalSeconds
        }
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-PnPUtilVersion {
    <#
    .SYNOPSIS
        Gets the version information of pnputil.exe.

    .OUTPUTS
        PSCustomObject with version information or $null if failed.

    .EXAMPLE
        $version = Get-PnPUtilVersion
        if ($version) { Write-Host "pnputil version: $($version.Version)" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $output = pnputil /? 2>&1 | Select-Object -First 10
        # Parse version from the output - this is approximate
        $versionLine = $output | Where-Object { $_ -match 'version|Version' } | Select-Object -First 1

        return [PSCustomObject]@{
            Available = $true
            Version = if ($versionLine) { $versionLine } else { "Unknown" }
            Path = (Get-Command pnputil).Source
        }
    }
    catch {
        Write-Log "pnputil.exe not available: $($_.Exception.Message)" -Level Warning
        return [PSCustomObject]@{
            Available = $false
            Version = $null
            Path = $null
        }
    }
}

function Test-PnPUtilAvailable {
    <#
    .SYNOPSIS
        Tests if pnputil.exe is available on the system.

    .OUTPUTS
        Boolean indicating availability.

    .EXAMPLE
        if (Test-PnPUtilAvailable) { Write-Host "pnputil is available" }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $null = Get-Command pnputil -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# ============================================================================
# EXPORTS
# ============================================================================

Export-ModuleMember -Function @(
    'Install-DriversFromPath',
    'Install-SingleDriver',
    'Export-DriverPackage',
    'Get-PnPUtilVersion',
    'Test-PnPUtilAvailable'
)

