#requires -Version 5.1

function Set-RegistryValue {
    <#
    .SYNOPSIS
        Creates or updates a registry value under the specified path.
    .DESCRIPTION
        Ensures the key exists and then writes the provided value using the requested type.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $Value,
        [ValidateSet('String','DWord','Binary','ExpandString','MultiString','QWord')]
        [string]$Type = 'String'
    )
    if (-not (Test-Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create registry key')) {
            $null = New-Item -Path $Path -Force -ErrorAction Stop
        } else {
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$Path::$Name", 'Set registry value')) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
    }
}

function Set-IntuneSuccess {
    <#
    .SYNOPSIS
        Records successful Intune application installation metadata.
    .PARAMETER AppName
        Application identifier to mark as completed.
    .PARAMETER Version
        Optional version string stored with the success marker.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,
        [string]$Version = '1.0.0'
    )
    if ($PSCmdlet.ShouldProcess($AppName, 'Set Intune success marker')) {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\WinDeploy\Intune' -Name $AppName -Value $Version -Confirm:$false
    }
}

function Set-DeploymentStatus {
    <#
    .SYNOPSIS
        Tracks deployment step outcomes under the WinDeploy registry hive.
    .DESCRIPTION
        Persists status, timestamp, optional error details, and version metadata.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Running')]
        [string]$Status,
        [string]$ErrorMessage,
        [int]$ExitCode,
        [string]$Version
    )
    $key = "HKLM:\SOFTWARE\WinDeploy\Deployment\Steps\$StepName"

    if (-not (Test-Path $key)) {
        if ($PSCmdlet.ShouldProcess($key, 'Create deployment status key')) {
            $null = New-Item -Path $key -Force -ErrorAction Stop
        } else {
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$key::Status", 'Update deployment status values')) {
        Set-ItemProperty -Path $key -Name 'Status' -Value $Status -Type String -Force
        Set-ItemProperty -Path $key -Name 'Timestamp' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force
        if ($ExitCode) { Set-ItemProperty -Path $key -Name 'ExitCode' -Value $ExitCode -Type DWord -Force }
        if ($ErrorMessage) { Set-ItemProperty -Path $key -Name 'ErrorMessage' -Value $ErrorMessage -Type String -Force }
        if ($Version) { Set-ItemProperty -Path $key -Name 'Version' -Value $Version -Type String -Force }
    }
}

function Get-DeploymentStatus {
    <#
    .SYNOPSIS
        Retrieves stored deployment status information for a step.
    .PARAMETER StepName
        Name of the deployment step to query.
    .OUTPUTS
        PSCustomObject with status details, or $null if no record exists.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$StepName)
    $key = "HKLM:\SOFTWARE\WinDeploy\Deployment\Steps\$StepName"
    if (-not (Test-Path $key)) { return $null }
    $status = Get-ItemProperty -Path $key -ErrorAction Stop
    return [PSCustomObject]@{
        StepName = $StepName
        Status = $status.Status
        Timestamp = $status.Timestamp
        ExitCode = if ($status.PSObject.Properties['ExitCode']) { $status.ExitCode } else { $null }
        ErrorMessage = if ($status.PSObject.Properties['ErrorMessage']) { $status.ErrorMessage } else { $null }
        Version = if ($status.PSObject.Properties['Version']) { $status.Version } else { $null }
    }
}

Export-ModuleMember -Function @(
    'Set-RegistryValue', 'Set-IntuneSuccess',
    'Set-DeploymentStatus', 'Get-DeploymentStatus'
)