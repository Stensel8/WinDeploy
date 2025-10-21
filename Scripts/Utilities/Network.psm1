#requires -Version 5.1

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests if network connection is available.

    .DESCRIPTION
        Performs a lightweight network connectivity test by attempting to reach a known URL.
        Uses HEAD request to minimize data transfer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$TestUrl = "https://raw.githubusercontent.com",
        [int]$TimeoutSeconds = 5
    )

    try {
        $request = [System.Net.WebRequest]::Create($TestUrl)
        $request.Timeout = $TimeoutSeconds * 1000
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

function Wait-ForNetworkStability {
    <#
    .SYNOPSIS
        Waits for stable network connectivity using robust retry pattern.

    .DESCRIPTION
        Uses do-until loop to wait for network connectivity with configurable retries.
        Returns true if network becomes available, false if max retries exceeded.
        Provides visual feedback during the wait process.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 10,
        [switch]$ContinuousCheck,
        [switch]$Silent
    )

    $attempt = 0

    if (-not $Silent) {
        Write-Host "Testing network connectivity..." -ForegroundColor Cyan
    }

    do {
        $attempt++

        if (Test-NetworkConnectivity) {
            if (-not $Silent) {
                Write-Host "Network connectivity confirmed (attempt $attempt/$MaxRetries)" -ForegroundColor Green
            }

            if ($ContinuousCheck) {
                if (-not $Silent) {
                    Write-Host "Performing stability check..." -ForegroundColor Cyan
                }

                $stableChecks = 0
                do {
                    Start-Sleep -Seconds 2
                    if (Test-NetworkConnectivity) {
                        $stableChecks++
                    } else {
                        if (-not $Silent) {
                            Write-Host "Network unstable, retrying..." -ForegroundColor Yellow
                        }
                        break
                    }
                } until ($stableChecks -ge 3)

                if ($stableChecks -ge 3) {
                    if (-not $Silent) {
                        Write-Host "Network connection is stable" -ForegroundColor Green
                    }
                    return $true
                }
            } else {
                return $true
            }
        }

        if ($attempt -lt $MaxRetries) {
            if (-not $Silent) {
                Write-Host "Network not available (attempt $attempt/$MaxRetries). Waiting $DelaySeconds seconds..." -ForegroundColor Yellow
            }
            Start-Sleep -Seconds $DelaySeconds
        }

    } until ($attempt -ge $MaxRetries)

    if (-not $Silent) {
        Write-Host "Network connectivity check failed after $MaxRetries attempts" -ForegroundColor Red
    }
    return $false
}

Export-ModuleMember -Function @('Test-NetworkConnectivity', 'Wait-ForNetworkStability')
