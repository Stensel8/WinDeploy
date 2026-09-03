# ============================================================================
# Apply-Tweaks.ps1
# Applies a WinUtil (ChrisTitusTech) tweak preset.
# Standalone script - can be deployed via any management tool.
#
# This step downloads and runs a THIRD-PARTY script from christitus.com, so it
# is opt-in: the operator has to confirm with Y before anything runs.
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    # Ask  = prompt the operator (default)
    # Yes  = run without prompting
    # No   = skip this step
    [ValidateSet('Ask', 'Yes', 'No')]
    [string]$Tweaks = 'Ask',

    # WinUtil preset to apply. See Get-PresetSummary below for what each does.
    [ValidateSet('Standard', 'Minimal', 'Advanced')]
    [string]$Preset = 'Standard',

    # How long the prompt waits for a keypress before falling back to "No".
    # Keeps unattended deployments from hanging forever.
    [int]$PromptTimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$WinUtilUrl = 'https://christitus.com/win'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = if ($PSCommandPath) { [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) } else { "Apply-Tweaks" }
    $logFile = Join-Path $logDir "$scriptName.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Warning $Message } else { Write-Output $Message }
}

# Prompts for Y/N with a timeout. Returns $DefaultYes when the session is not
# interactive or nothing is typed in time, so a zero-touch deployment (which
# may run in a hidden window) never blocks.
function Read-YesNoWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [int]$TimeoutSeconds = 90,
        [switch]$DefaultYes
    )

    $default = [bool]$DefaultYes
    $defaultLabel = if ($default) { 'Y' } else { 'N' }

    # Work out whether anyone can actually answer. UserInteractive alone is not
    # enough: it is $true for any process in a user session, including one
    # started with a redirected stdin or from a scheduled task, where waiting
    # out the full timeout would stall the deployment for nothing.
    $interactive = [Environment]::UserInteractive
    if ($interactive) {
        try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { $interactive = $false }
    }
    if ($interactive) {
        # Hosts without a real console (ISE, some job runners) throw here.
        try { $null = $Host.UI.RawUI.KeyAvailable } catch { $interactive = $false }
    }
    if (-not $interactive) {
        Write-Host "$Question [Y/N] -> no interactive console, using default: $defaultLabel" -ForegroundColor Cyan
        return $default
    }

    # Drain anything already buffered so a stray keypress doesn't answer for us.
    try {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    } catch {
        Write-Debug "Could not drain the input buffer: $($_.Exception.Message)"
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastShown = -1
    while ((Get-Date) -lt $deadline) {
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        # Repaint every 5s rather than every second: Start.ps1 runs a transcript,
        # and a once-per-second countdown fills the log with redraw lines.
        if ($lastShown -lt 0 -or ($lastShown - $remaining) -ge 5) {
            Write-Host ("`r{0} [Y/N] (default {1} in {2}s)   " -f $Question, $defaultLabel, $remaining) -NoNewline -ForegroundColor Yellow
            $lastShown = $remaining
        }
        if ($Host.UI.RawUI.KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.Character -eq 'y' -or $key.Character -eq 'Y') { Write-Host "`r$Question [Y/N] -> Yes                    " -ForegroundColor Green; return $true }
            if ($key.Character -eq 'n' -or $key.Character -eq 'N') { Write-Host "`r$Question [Y/N] -> No                     " -ForegroundColor Cyan;  return $false }
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host ("`r{0} [Y/N] -> timed out, using default: {1}          " -f $Question, $defaultLabel) -ForegroundColor Cyan
    return $default
}

# What each preset changes, so the operator can decide before pressing Y.
function Get-PresetSummary {
    param([string]$Name)
    switch ($Name) {
        'Minimal' {
            return @(
                "Disable consumer features (stops Windows re-installing bloatware)",
                "Disable WPBT (blocks OEM firmware-injected binaries)",
                "Set non-essential services to manual start",
                "Disable telemetry"
            )
        }
        'Advanced' {
            return @(
                "Everything in Standard, plus:",
                "Disable Store search, widgets and Windows AI/Recall",
                "Restore the classic Start menu and right-click menu",
                "Remove OneDrive"
            )
        }
        default {
            return @(
                "Create a system restore point first",
                "Disable activity history, location tracking and telemetry",
                "Disable consumer features (stops Windows re-installing bloatware)",
                "Disable WPBT (blocks OEM firmware-injected binaries)",
                "Disable Delivery Optimization peer-to-peer update sharing",
                "Set non-essential services to manual start",
                "Disable Explorer folder-type auto-discovery",
                "Enable 'End task' in the taskbar right-click menu",
                "Run disk cleanup and delete temporary files"
            )
        }
    }
}

Write-DeployLog "=== WinUtil tweaks ($Preset preset) ==="

switch ($Tweaks) {
    'Yes' { $runTweaks = $true }
    'No'  { $runTweaks = $false }
    default {
        Write-Output ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " Optional: WinUtil tweaks - '$Preset' preset" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " This downloads and runs a third-party script:" -ForegroundColor Gray
        Write-Host "   $WinUtilUrl  (ChrisTitusTech/winutil)" -ForegroundColor Gray
        Write-Host ""
        Write-Host " The '$Preset' preset will:" -ForegroundColor Gray
        foreach ($line in (Get-PresetSummary -Name $Preset)) {
            Write-Host "   - $line" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host " Skipping this step leaves the rest of the deployment intact." -ForegroundColor Gray
        Write-Host ""
        $runTweaks = Read-YesNoWithTimeout -Question " Run WinUtil '$Preset' tweaks now?" -TimeoutSeconds $PromptTimeoutSeconds
        Write-Output ""
    }
}

if (-not $runTweaks) {
    Write-DeployLog "WinUtil tweaks skipped (not confirmed). Re-run with -Tweaks Yes to apply them later."
    exit 0
}

try {
    Write-DeployLog "Running WinUtil with the '$Preset' preset. This can take several minutes..."

    # Run WinUtil in its own process. It manages its own transcript, runspace
    # pool and global state, and calls Stop-Transcript when it finishes - none
    # of which should touch the deployment session that called us.
    $command = "& ([ScriptBlock]::Create((irm $WinUtilUrl))) -Preset $Preset"
    $hostExe = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($hostExe)) { $hostExe = 'powershell.exe' }

    $proc = Start-Process -FilePath $hostExe `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0) {
        Write-DeployLog "SUCCESS: WinUtil '$Preset' preset applied."
    } else {
        Write-DeployLog "WinUtil exited with code $($proc.ExitCode). Review C:\WinDeploy\Logs and the WinUtil log for details." -IsError
    }
} catch {
    Write-DeployLog "Failed to run WinUtil: $($_.Exception.Message)" -IsError
}

Write-Output ""
Write-Output "Note: some WinUtil tweaks (services, Explorer settings) only take effect after a restart."
exit 0
