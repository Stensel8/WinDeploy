#requires -Version 5.1

# Module-scoped configuration
if (-not $script:Config) {
    $script:Config = @{
        LogPath = 'C:\WinDeploy\Logs'
        LogName = 'Deployment.log'
        TranscriptActive = $false
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages with separate console and file output.

    .DESCRIPTION
        Dual-output logging system:
        - Console: Shows user-friendly, summarized messages (clean, no timestamps)
        - Log file: Records detailed, verbose information (with timestamps)

    .PARAMETER Message
        The detailed message to write to the log file.
        If -ConsoleMessage is not provided, this is also shown on screen.

    .PARAMETER ConsoleMessage
        Optional. User-friendly message shown on screen.
        If omitted, uses -Message for both screen and log.

    .PARAMETER Level
        Log level: Info, Success, Warning, Error, Verbose, Debug

    .PARAMETER NoConsole
        Suppresses console output. Message only goes to log file.

    .EXAMPLE
        Write-Log "Installing application: Microsoft.Office v16.0.12345" -ConsoleMessage "Installing Microsoft Office"
        # Screen: "Installing Microsoft Office"
        # Log:    "[2025-01-15 10:30:45] [Info] Installing application: Microsoft.Office v16.0.12345"

    .EXAMPLE
        Write-Log "Detailed registry change: HKLM:\Software\..." -NoConsole
        # Screen: (nothing)
        # Log:    "[2025-01-15 10:30:45] [Info] Detailed registry change: HKLM:\Software\..."
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification='Custom logging helper used across deployment tooling')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [string]$ConsoleMessage,

        [ValidateSet('Info','Success','Warning','Error','Verbose','Debug')]
        [string]$Level = 'Info',

        [switch]$NoConsole
    )
    process {
        # Handle empty messages - just print blank line, don't log
        if ([string]::IsNullOrEmpty($Message)) {
            if (-not $NoConsole) {
                Write-Host ""
            }
            # Don't write to log file for empty messages
            return
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $color = @{
            Success = 'Green'; Warning = 'Yellow'; Error = 'Red'
            Info = 'Cyan'; Verbose = 'Gray'; Debug = 'Magenta'
        }[$Level]

        # Determine what to show on console
        $displayMessage = if ($ConsoleMessage) { $ConsoleMessage } else { $Message }

        # Write to console (user-friendly, no timestamp)
        if (-not $NoConsole) {
            Write-Host $displayMessage -ForegroundColor $color
        }

        # Write detailed log entry to log file (captured by transcript but hidden from console)
        # PowerShell transcripts capture Write-Information when $InformationPreference allows it
        # We use 6> redirection to suppress console output while transcript still captures it
        $logEntry = "[$timestamp] [$Level] $Message"
        $InformationPreference = 'SilentlyContinue'  # Don't show on console
        Write-Information $logEntry  # Transcript will still capture this
    }
}

function Write-UserMessage {
    <#
    .SYNOPSIS
        Writes a message to console only (not logged to file).

    .DESCRIPTION
        Used for purely visual/UI elements like progress indicators,
        banners, and formatting that don't need to be in the log file.

    .PARAMETER Message
        The message to display.

    .PARAMETER Color
        Console color. Default: Gray

    .PARAMETER NoNewline
        Suppresses newline after message.

    .EXAMPLE
        Write-UserMessage "Installing applications..." -Color Cyan
        Write-UserMessage "[1/5] " -NoNewline -Color Gray
        Write-UserMessage "Installing Office" -Color White
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')]
        [string]$Color = 'Gray',

        [switch]$NoNewline
    )

    # Handle empty messages (print blank line)
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ""
        return
    }

    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Initialize-LogDirectory {
    <#
    .SYNOPSIS
        Creates a directory if it doesn't exist.
    .DESCRIPTION
        Generic directory initialization with smart messaging based on path.
    #>
    [CmdletBinding()]
    param([string]$Path = $script:Config.LogPath)
    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
        # Smart message based on directory type
        $dirType = if ($Path -match 'Download') { 'download' } elseif ($Path -match 'Logs') { 'log' } else { 'working' }
        Write-Log "Created $dirType directory: $Path" -Level Info
    }
}

function Start-Logging {
    <#
    .SYNOPSIS
        Starts transcript logging for the current deployment script.
    .DESCRIPTION
        Ensures the log directory exists, rotates large log files, and starts a PowerShell transcript.
    .PARAMETER LogPath
        Destination path where the transcript will be written.
    .PARAMETER LogName
        File name for the transcript log.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string]$LogPath = $script:Config.LogPath,
        [string]$LogName = $script:Config.LogName
    )
    $logFile = Join-Path -Path $LogPath -ChildPath $LogName
    if (-not $PSCmdlet.ShouldProcess($logFile, 'Start logging')) {
        return
    }

    $script:Config.LogPath = $LogPath
    $script:Config.LogName = $LogName

    Initialize-LogDirectory -Path $LogPath
    if (Test-Path $logFile) {
        $size = (Get-Item $logFile).Length / 1MB
        if ($size -gt 10) {
            $backupPath = Join-Path $LogPath ($LogName -replace '\.log$', ".old.log")
            Move-Item -Path $logFile -Destination $backupPath -Force
            Write-Log "Rotated log file (was $([math]::Round($size,2))MB)" -Level Info
        }
    }
    try {
        # If a transcript is already active, Stop-Transcript first to avoid errors
        if ($script:Config.TranscriptActive) {
            try {
                Stop-Transcript | Out-Null
            } catch {
                Write-Warning "Failed to stop existing transcript prior to restart: $($_.Exception.Message)"
            }
            $script:Config.TranscriptActive = $false
        }
        Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
        $script:Config.TranscriptActive = $true
        Write-Log "Started logging to: $logFile" -Level Info
    } catch {
        # If Start-Transcript throws because a transcript is already active (or other benign reasons), mark as active
        $script:Config.TranscriptActive = $true
        Write-Warning "Failed to start transcript cleanly: $($_.Exception.Message)"
        Write-Log "Transcript already active; continuing logging to: $logFile" -Level Info
    }
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Stops the active transcript session for the deployment script.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()
    if (-not $script:Config.TranscriptActive) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess('Active transcript', 'Stop logging')) {
        return
    }

    try {
        Stop-Transcript | Out-Null
        $script:Config.TranscriptActive = $false
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
}

function Initialize-Script {
    <#
    .SYNOPSIS
        Centralized initialization for WinDeploy scripts with per-script logging.

    .PARAMETER LogName
        Optional. Log file name. If not provided, uses calling script name with .log extension.

    .PARAMETER RequireAdmin
        When provided, enforces elevation check via Test-AdminRights from System module.
    #>
    [CmdletBinding()]
    param(
        [string]$LogName,
        [switch]$RequireAdmin
    )

    # Admin check requires System module to be loaded
    if ($RequireAdmin) {
        $testAdminCmd = Get-Command Test-AdminRights -ErrorAction SilentlyContinue
        if ($testAdminCmd) {
            # Call the function using & operator
            if (-not (& $testAdminCmd)) {
                throw "This script requires administrative privileges"
            }
        } else {
            # Fallback if System module not loaded
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "This script requires administrative privileges"
            }
        }
    }

    # Auto-detect log name from calling script if not provided
    if (-not $LogName) {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $LogName = [System.IO.Path]::GetFileNameWithoutExtension($callingScript) + '.log'
            } else {
                $LogName = 'Deployment.log'
            }
        } else {
            $LogName = 'Deployment.log'
        }
    }

    $script:Config.LogName = $LogName
    Initialize-LogDirectory
    Start-Logging

    # Disable interactive confirmation prompts unless explicitly requested
    if (-not $PSBoundParameters.ContainsKey('Confirm')) {
        try {
            if ($ConfirmPreference -ne 'None') {
                Set-Variable -Name ConfirmPreference -Value 'None' -Scope Global
            }
        } catch {
            Write-Warning "Unable to adjust ConfirmPreference: $($_.Exception.Message)"
        }
    }
}

function Complete-Script {
    <#
    .SYNOPSIS
        Finalizes logging after a deployment script completes.
    .DESCRIPTION
        Provides a shorthand wrapper around Stop-Logging for script cleanup.
    #>
    [CmdletBinding()]
    param()
    Stop-Logging
}

function Start-EmergencyTranscript {
    <#
    .SYNOPSIS
        Starts a transcript for logging even if modules fail to import.
    .PARAMETER LogName
        Optional log file name. Defaults to script name.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param([string]$LogName)
    $logRoot = 'C:\WinDeploy\Logs'
    if (-not (Test-Path $logRoot)) { $null = New-Item -Path $logRoot -ItemType Directory -Force }
    if (-not $LogName) {
        $LogName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) + '.log'
    }
    $bootstrapLog = Join-Path $logRoot $LogName
    if (-not $PSCmdlet.ShouldProcess($bootstrapLog, 'Start emergency transcript')) {
        return
    }
    try {
        if (-not (Get-Variable -Name BootstrapTranscript -Scope Script -ErrorAction SilentlyContinue)) {
            Start-Transcript -Path $bootstrapLog -Append -ErrorAction SilentlyContinue | Out-Null
            $script:BootstrapTranscript = $true
        }
    } catch {
        Write-Warning "Emergency transcript start failed: $($_.Exception.Message)"
    }
}

function Stop-EmergencyTranscript {
    <#
    .SYNOPSIS
        Stops the emergency transcript if started.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()
    try {
        if (Get-Variable -Name BootstrapTranscript -Scope Script -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess('Emergency transcript', 'Stop transcript')) {
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                Remove-Variable -Name BootstrapTranscript -Scope Script -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "Emergency transcript stop failed: $($_.Exception.Message)"
    }
}

# ============================================================================
# DEPLOYMENT FLOW OUTPUT HELPERS
# ============================================================================

function Write-SectionBanner {
    <#
    .SYNOPSIS
        Displays a section banner matching the deployment flow format.
    .EXAMPLE
        Write-SectionBanner -Title "EXECUTING DEPLOYMENT STEPS"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $separator = "=" * 60
    Write-UserMessage ""
    Write-UserMessage $separator -Color Cyan
    Write-UserMessage "  $Title" -Color Cyan
    Write-UserMessage $separator -Color Cyan
    Write-UserMessage ""
}

function Write-StepStart {
    <#
    .SYNOPSIS
        Displays the start of a deployment step.
    .EXAMPLE
        Write-StepStart -StepName "WinGet Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName
    )

    Write-UserMessage "[RUNNING] $StepName" -Color Cyan
}

function Write-StepComplete {
    <#
    .SYNOPSIS
        Displays the completion of a deployment step.
    .EXAMPLE
        Write-StepComplete -StepName "WinGet Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName
    )

    Write-UserMessage "$([char]0x221A) Completed: $StepName" -Color Green
}

function Write-StepExecuting {
    <#
    .SYNOPSIS
        Displays a sub-step execution message.
    .EXAMPLE
        Write-StepExecuting -Message "Executing with PowerShell 7"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-UserMessage " -> $Message" -Color Cyan
}

function Write-DeploymentSummary {
    <#
    .SYNOPSIS
        Displays the final deployment summary.
    .EXAMPLE
        Write-DeploymentSummary -SuccessCount 6 -FailedCount 0 -SkippedCount 0 -LogPath "C:\WinDeploy\Logs\Deploy-Device.log"
    #>
    [CmdletBinding()]
    param(
        [int]$SuccessCount = 0,
        [int]$FailedCount = 0,
        [int]$SkippedCount = 0,
        [string]$LogPath
    )

    $separator = "=" * 60
    Write-UserMessage ""
    Write-UserMessage $separator -Color Cyan
    Write-UserMessage "  DEPLOYMENT COMPLETE" -Color Green
    Write-UserMessage $separator -Color Cyan
    Write-UserMessage ""
    Write-UserMessage "Success: $SuccessCount" -Color Green
    Write-UserMessage "Failed: $FailedCount" -Color $(if ($FailedCount -gt 0) { 'Red' } else { 'Gray' })
    Write-UserMessage "Skipped: $SkippedCount" -Color $(if ($SkippedCount -gt 0) { 'Yellow' } else { 'Gray' })

    if ($LogPath) {
        Write-UserMessage ""
        Write-UserMessage "Log: $LogPath" -Color Cyan
    }

    Write-UserMessage ""
}

Export-ModuleMember -Function @(
    'Write-Log', 'Write-UserMessage', 'Initialize-LogDirectory', 'Start-Logging', 'Stop-Logging',
    'Initialize-Script', 'Complete-Script',
    'Start-EmergencyTranscript', 'Stop-EmergencyTranscript',
    'Write-SectionBanner', 'Write-StepStart', 'Write-StepComplete', 'Write-StepExecuting',
    'Write-DeploymentSummary'
) -Variable 'Config'