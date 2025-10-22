#requires -Version 5.1

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with retry logic using do-while pattern.

    .DESCRIPTION
        Implements robust retry mechanism with exponential backoff option.
        Validates network connectivity before network-dependent operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2,
        [switch]$ExponentialBackoff,
        [switch]$RequiresNetwork
    )

    $attempt = 0

    do {
        $attempt++

        try {
            # Validate network if required
            if ($RequiresNetwork -and $attempt -gt 1) {
                if (-not (Test-NetworkConnectivity)) {
                    Start-Sleep -Seconds 5
                    if (-not (Test-NetworkConnectivity)) {
                        throw "Network connectivity required but unavailable"
                    }
                }
            }

            $result = & $ScriptBlock
            return $result
        } catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            $delay = if ($ExponentialBackoff) {
                $DelaySeconds * [Math]::Pow(2, $attempt - 1)
            } else {
                $DelaySeconds
            }

            Start-Sleep -Seconds $delay
        }
    } while ($attempt -lt $MaxAttempts)
}

function Get-DeploymentScript {
    <#
    .SYNOPSIS
        Locates a deployment script in order: PSScriptRoot -> Download folder -> GitHub

    .DESCRIPTION
        Searches for deployment scripts in multiple locations:
        1. Same directory as calling script ($CallerScriptRoot)
        2. C:\WinDeploy\Download
        3. Downloads from GitHub if network is available

    .PARAMETER ScriptName
        Name of the script to locate (e.g., 'Install-Applications.ps1')

    .PARAMETER CallerScriptRoot
        The $PSScriptRoot of the calling script (auto-detected if not specified)

    .PARAMETER DownloadDirectory
        Override default download directory (C:\WinDeploy\Download)

    .OUTPUTS
        String path to the script if found, $null otherwise

    .EXAMPLE
        $scriptPath = Get-DeploymentScript -ScriptName 'Install-Drivers.ps1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [string]$CallerScriptRoot,

        [string]$DownloadDirectory = 'C:\WinDeploy\Download'
    )

    # Get caller's script root if not provided
    if (-not $CallerScriptRoot) {
        $CallerScriptRoot = (Get-PSCallStack)[1].ScriptName | Split-Path -Parent
    }

    $logAvailable = Get-Command Write-Log -ErrorAction SilentlyContinue

    # Check 1: Same directory as calling script
    $localPath = Join-Path $CallerScriptRoot $ScriptName
    if (Test-Path $localPath) {
        if ($logAvailable) {
            Write-Log "  -> Found $ScriptName in script directory" -Level Verbose
        }
        return $localPath
    }

    # Check 2: Download directory
    $downloadPath = Join-Path $DownloadDirectory $ScriptName
    if (Test-Path $downloadPath) {
        if ($logAvailable) {
            Write-Log "  -> Found $ScriptName in download directory" -Level Verbose
        }
        return $downloadPath
    }

    # Check 3: Try to download from GitHub
    if (Get-Command Test-NetworkConnectivity -ErrorAction SilentlyContinue) {
        if (Test-NetworkConnectivity) {
            if ($logAvailable) {
                Write-Log "  -> Downloading $ScriptName from GitHub..." -Level Info
            }
            if (Get-Command Get-RemoteScript -ErrorAction SilentlyContinue) {
                if (Get-RemoteScript -ScriptName $ScriptName) {
                    return $downloadPath
                }
            }
        }
    }

    if ($logAvailable) {
        Write-Log "  -> ERROR: Could not find $ScriptName" -Level Error
    }
    return $null
}

function Write-DeploymentBanner {
    <#
    .SYNOPSIS
        Displays the WinDeploy ASCII art banner.

    .DESCRIPTION
        Outputs the standardized WinDeploy logo banner with customizable title.

    .PARAMETER Title
        Optional title to display below the banner (default: "Windows Device Deployment Automation Toolkit")

    .PARAMETER ShowVersion
        If specified, displays PowerShell version and script path information

    .PARAMETER ScriptPath
        Path to the current script (for display purposes)

    .EXAMPLE
        Write-DeploymentBanner -ShowVersion -ScriptPath $PSCommandPath
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Windows Device Deployment Automation Toolkit",
        [switch]$ShowVersion,
        [string]$ScriptPath
    )

    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host ".;%%%%?:                                                              " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%*,,:?%,                                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "*%;  .*%;.                                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+%?*??*??*;,.    .,,.                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  .,:,. .,;*??*::*?????;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            .:+?%?:..,;%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               +%:     ?%,                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               :%?:..,+%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "             .:?%*????*;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            :*%+, ....                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    ....  :*%*,                                           .       ..  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " .;****?**%*,    .*****:.    ,****+.   .**+. ;*,    +*, ;*:.   .+***+," -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".*?:...,;%?.     .%%,,*S:    :S*....   ,%%%+ *%,    *S:+%+.    +S+.;%?" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%.      ;%+     .%%. ;S+    :%?++;    ,%*+%:*%,    *%?%+      *%: .%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ";%.      ;%;     .%%. ;S+    :%*,,.    ,%*.???%,    *%;??,     *S: ,%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+?;,..,+%+.     .%%;;??,    :S?:::.   ,%? ,%%%,    *S:,%%,    ;%*:+%+" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  ,+*???+,       .;;;;:.     ,;;;+;.   .;:  :;;.    :;, ,;:.    ,;+;:." -ForegroundColor Red
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host "         $Title" -ForegroundColor Gray
    Write-Host ""

    if ($ShowVersion) {
        Write-Host "    PowerShell: " -NoNewline -ForegroundColor Gray
        Write-Host "$($PSVersionTable.PSVersion)" -ForegroundColor White
        if ($ScriptPath) {
            Write-Host "    Script: " -NoNewline -ForegroundColor Gray
            Write-Host "$ScriptPath" -ForegroundColor White
        }
        Write-Host ""
    }
}

Export-ModuleMember -Function @(
    'Invoke-WithRetry',
    'Get-DeploymentScript',
    'Write-DeploymentBanner'
)
