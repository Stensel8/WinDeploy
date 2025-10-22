# WinDeploy Hostname Generator
# Part of the WinDeploy Automation Toolkit
# See Releases for current version and CHANGELOG.md for changes

#requires -Version 5.1

<#
.SYNOPSIS
    Generates a new hostname based on the computer's serial number.

.DESCRIPTION
    Retrieves the system's BIOS serial number and formats it using the last 5 characters
    prefixed with 'PC-' to create a standardized hostname (e.g., PC-12345).

.EXAMPLE
    .\Generate-Hostname.ps1

.EXAMPLE
    $newHostname = & .\Generate-Hostname.ps1
    Rename-Computer -NewName $newHostname -Force

.OUTPUTS
    String. Returns the formatted hostname (e.g., "PC-12345").

.NOTES
    Requires : PowerShell 5.1+
#>
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Handle remote execution where $PSScriptRoot is empty
# When script is invoked via Invoke-RestMethod piped to Invoke-Expression (irm | iex),
# PowerShell doesn't populate $PSScriptRoot, preventing module imports from finding Utilities folder
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }

# Import required modules
$possiblePaths = @(
    (Join-Path $scriptRoot 'Utilities'),
    'C:\WinDeploy\Download\Utilities',
    'C:\WinDeploy\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'Generate-Hostname.log'
Initialize-Script

try {
    $serial = (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber

    if ([string]::IsNullOrWhiteSpace($serial)) {
        Write-Log "Serial number not found, returning PC-UNKNOWN" -Level Warning
        return 'PC-UNKNOWN'
    }

    $serial = $serial.Trim()

    if ($serial.Length -lt 5) {
        $hostname = "PC-$serial"
    } else {
        $hostname = 'PC-{0}' -f $serial.Substring($serial.Length - 5)
    }

    Write-Log "Generated hostname: $hostname" -Level Success
    return $hostname

} catch {
    Write-Log "Failed to generate hostname: $_" -Level Error
    return 'PC-Name'
} finally {
    Complete-Script
}
