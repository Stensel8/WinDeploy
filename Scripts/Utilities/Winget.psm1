#requires -Version 5.1

function Test-WinGet {
    <#
    .SYNOPSIS
        Checks if WinGet is installed, functional, and returns path and version info.

    .DESCRIPTION
        Unified WinGet detection function that locates winget.exe, verifies it works,
        and includes exit code descriptions for troubleshooting.

    .PARAMETER ReturnPath
        If specified, returns the path to winget.exe instead of PSCustomObject.
        Returns $null if WinGet is not found.

    .OUTPUTS
        [PSCustomObject] - Default: Returns object with WinGetPath, IsAvailable, Version properties
        [String] - When ReturnPath specified: Returns path to winget.exe or $null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([switch]$ReturnPath)

    $result = [PSCustomObject]@{
        WinGetPath = $null
        IsAvailable = $false
        Version = $null
    }

    try {
        # Refresh PATH from machine and user scopes to pick up new installs
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('PATH','User')

        # Try to find winget in PATH first
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $result.WinGetPath = $wingetCmd.Source
        } else {
            # Search WindowsApps folder
            $paths = @(
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
                "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
            )

            foreach ($path in $paths) {
                $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
                if ($resolved) {
                    if ($resolved -is [array]) {
                        $resolved = $resolved | Sort-Object {
                            [version]($_.Path -replace '^.*_(\d+\.\d+\.\d+\.\d+)_.*', '$1')
                        } -Descending | Select-Object -First 1
                    }
                    $result.WinGetPath = $resolved.Path
                    break
                }
            }
        }

        # If path found, test if it works
        if ($result.WinGetPath) {
            $versionOutput = & $result.WinGetPath --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.IsAvailable = $true
                $result.Version = $versionOutput -replace '^v', ''
            }
        }
    } catch {
        Write-Verbose "WinGet detection failed: $($_.Exception.Message)"
    }

    if ($ReturnPath) { return $result.WinGetPath }
    return $result
}

function Get-WinGetPath {
    <#
    .SYNOPSIS
        Returns the full path to winget.exe if available, else $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Test-WinGet -ReturnPath)
}

function Test-WinGetFunctional {
    <#
    .SYNOPSIS
        Tests that winget is present and working. Returns hashtable with Path and Version.

    .DESCRIPTION
        Ensures WinGet is functional and throws an error if not found or not working.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $wg = Test-WinGet

    if (-not $wg.IsAvailable) {
        throw 'WinGet not found or not functional. Install App Installer (winget) from Microsoft Store.'
    }

    return @{
        Path = $wg.WinGetPath
        Version = $wg.Version
    }
}

function Repair-WinGet {
    <#
    .SYNOPSIS
        Intelligently repairs or installs WinGet and its dependencies.

    .DESCRIPTION
        Smart function that detects WinGet status and repairs/installs as needed.
        Handles dependencies, registration, and PATH configuration automatically.

    .PARAMETER IncludeDependencies
        Ensures VCLibs and UI.Xaml dependencies are installed.

    .OUTPUTS
        PSCustomObject with RepairPerformed, Success, Message, WinGetPath, Version properties.

    .EXAMPLE
        Repair-WinGet -IncludeDependencies
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeDependencies
    )

    $logCommand = Get-Command Write-Log -ErrorAction SilentlyContinue
    $logWriter = {
        param([string]$Message, [string]$Level)
        if ($logCommand) {
            Write-Log $Message -Level $Level
        } else {
            $colors = @{Info='Cyan'; Success='Green'; Warning='Yellow'; Error='Red'; Verbose='Gray'}
            $color = $colors[$Level]
            if ($color) { Write-Host $Message -ForegroundColor $color }
            else { Write-Host $Message }
        }
    }

    $result = [PSCustomObject]@{
        RepairPerformed = $false
        Success = $false
        Message = ''
        WinGetPath = $null
        Version = $null
    }

    try {
        # Step 1: Test current WinGet status
        & $logWriter 'Checking WinGet status...' 'Info'
        $wg = Test-WinGet

        if ($wg.IsAvailable) {
            & $logWriter "WinGet already functional (v$($wg.Version))" 'Success'
            $result.Success = $true
            $result.Message = 'WinGet already functional'
            $result.WinGetPath = $wg.WinGetPath
            $result.Version = $wg.Version

            # Still check dependencies if requested
            if ($IncludeDependencies) {
                & $logWriter 'Verifying dependencies...' 'Verbose'
                $depResult = Confirm-WinGetDependencyStatus
                if (-not $depResult.AllSatisfied) {
                    & $logWriter 'Installing missing dependencies...' 'Info'
                    Install-WinGetSystemPrerequisite
                }
            }

            return $result
        }

        # Step 2: WinGet needs repair/installation
        & $logWriter 'WinGet repair/installation required' 'Warning'
        $result.RepairPerformed = $true

        # Step 3: Check admin privileges
        if (-not (Test-AdminPrivilege)) {
            $result.Message = 'Administrator privileges required for WinGet installation'
            & $logWriter $result.Message 'Error'
            return $result
        }

        # Step 4: Install dependencies first
        & $logWriter 'Installing WinGet system dependencies...' 'Info'
        Install-WinGetSystemPrerequisite

        # Step 5: Install/Repair WinGet itself
        & $logWriter 'Installing WinGet package manager...' 'Info'
        $installResult = Install-WinGetPackage

        if (-not $installResult.Success) {
            $result.Message = "WinGet installation failed: $($installResult.Message)"
            & $logWriter $result.Message 'Error'
            return $result
        }

        # Step 6: Register WinGet
        & $logWriter 'Registering WinGet...' 'Info'
        Register-WinGetPackage

        # Step 7: Refresh PATH
        & $logWriter 'Refreshing environment PATH...' 'Info'
        Update-SessionPath

        # Step 8: Verify installation
        & $logWriter 'Verifying WinGet installation...' 'Info'
        Start-Sleep -Seconds 3
        $wg = Test-WinGet

        if ($wg.IsAvailable) {
            & $logWriter "WinGet successfully installed (v$($wg.Version))" 'Success'
            $result.Success = $true
            $result.Message = 'WinGet installed successfully'
            $result.WinGetPath = $wg.WinGetPath
            $result.Version = $wg.Version
        } else {
            $result.Message = 'WinGet installed but not detected. Restart may be required.'
            & $logWriter $result.Message 'Warning'
        }

    } catch {
        $result.Message = "Exception during WinGet repair: $($_.Exception.Message)"
        & $logWriter $result.Message 'Error'
    }

    return $result
}

function Confirm-WinGetDependencyStatus {
    <#
    .SYNOPSIS
        Checks if WinGet dependencies are installed.

    .OUTPUTS
        PSCustomObject with AllSatisfied, VCLibs, UIXaml properties.
    #>
    [CmdletBinding()]
    param()

    $vcLibs = [bool](Get-AppxPackage -Name '*VCLibs*140*UWPDesktop*' -ErrorAction SilentlyContinue)
    $uiXaml = [bool](Get-AppxPackage -Name '*UI.Xaml*' -ErrorAction SilentlyContinue)

    return [PSCustomObject]@{
        AllSatisfied = ($vcLibs -and $uiXaml)
        VCLibs = $vcLibs
        UIXaml = $uiXaml
    }
}

function Install-WinGetSystemPrerequisite {
    <#
    .SYNOPSIS
        Installs WinGet system dependencies (VCLibs, UI.Xaml, VCRedist).

    .DESCRIPTION
        Downloads and installs required dependencies from Microsoft/GitHub.
        Handles both user and system context installations.
    #>
    [CmdletBinding()]
    param()

    $logCommand = Get-Command Write-Log -ErrorAction SilentlyContinue
    $logWriter = {
        param([string]$Message, [string]$Level)
        if ($logCommand) {
            Write-Log $Message -Level $Level
        } else {
            $colors = @{Info='Cyan'; Success='Green'; Warning='Yellow'; Error='Red'; Verbose='Gray'}
            $color = $colors[$Level]
            if ($color) { Write-Host $Message -ForegroundColor $color }
            else { Write-Host $Message }
        }
    }

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') { $arch = 'x64' }
    elseif ($arch -eq 'ARM64') { $arch = 'arm64' }
    else { $arch = 'x86' }

    $isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -match 'SYSTEM'

    try {
        # Check existing dependencies
    $depStatus = Confirm-WinGetDependencyStatus

        # Install VCLibs if missing
        if (-not $depStatus.VCLibs) {
            & $logWriter 'Installing Microsoft.VCLibs.140.00.UWPDesktop...' 'Info'

            $vcLibsUrl = "https://aka.ms/Microsoft.VCLibs.${arch}.14.00.Desktop.appx"
            $vcLibsPath = Join-Path $env:TEMP "VCLibs_${arch}.appx"

            Invoke-WebRequest -Uri $vcLibsUrl -OutFile $vcLibsPath -UseBasicParsing

            if ($isSystem) {
                Add-AppxProvisionedPackage -Online -PackagePath $vcLibsPath -SkipLicense | Out-Null
            } else {
                Add-AppxPackage -Path $vcLibsPath | Out-Null
            }

            Remove-Item $vcLibsPath -Force -ErrorAction SilentlyContinue
            & $logWriter 'VCLibs installed successfully' 'Success'
        } else {
            & $logWriter 'VCLibs already installed' 'Verbose'
        }

        # Install UI.Xaml if missing
        if (-not $depStatus.UIXaml) {
            & $logWriter 'Installing Microsoft.UI.Xaml.2.8...' 'Info'

            # Try to get latest version from WinGet dependencies
            $xamlUrl = Get-WingetDownloadUrl -Match "Microsoft.UI.Xaml.*${arch}.appx"

            if (-not $xamlUrl) {
                # Fallback to known working version
                $xamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.${arch}.appx"
            }

            $xamlPath = Join-Path $env:TEMP "UIXaml_${arch}.appx"

            Invoke-WebRequest -Uri $xamlUrl -OutFile $xamlPath -UseBasicParsing

            if ($isSystem) {
                Add-AppxProvisionedPackage -Online -PackagePath $xamlPath -SkipLicense | Out-Null
            } else {
                Add-AppxPackage -Path $xamlPath | Out-Null
            }

            Remove-Item $xamlPath -Force -ErrorAction SilentlyContinue
            & $logWriter 'UI.Xaml installed successfully' 'Success'
        } else {
            & $logWriter 'UI.Xaml already installed' 'Verbose'
        }

        # Install VCRedist if missing (required for some scenarios)
        if (-not (Test-VCRedistInstalled)) {
            & $logWriter 'Installing Visual C++ Redistributable...' 'Info'

            $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.${arch}.exe"
            $vcRedistPath = Join-Path $env:TEMP "vc_redist_${arch}.exe"

            Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing

            $process = Start-Process -FilePath $vcRedistPath -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru

            Remove-Item $vcRedistPath -Force -ErrorAction SilentlyContinue

            if ($process.ExitCode -in @(0, 1638, 3010)) {
                & $logWriter 'VCRedist installed successfully' 'Success'
            } else {
                & $logWriter "VCRedist exit code: $($process.ExitCode)" 'Warning'
            }
        } else {
            & $logWriter 'VCRedist already installed' 'Verbose'
        }

    } catch {
        & $logWriter "Error installing dependencies: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Install-WinGetPackage {
    <#
    .SYNOPSIS
        Installs the WinGet package (DesktopAppInstaller).

    .OUTPUTS
        PSCustomObject with Success and Message properties.
    #>
    [CmdletBinding()]
    param()

    $logCommand = Get-Command Write-Log -ErrorAction SilentlyContinue
    $logWriter = {
        param([string]$Message, [string]$Level)
        if ($logCommand) {
            Write-Log $Message -Level $Level
        } else {
            $colors = @{Info='Cyan'; Success='Green'; Warning='Yellow'; Error='Red'}
            $color = $colors[$Level]
            if ($color) { Write-Host $Message -ForegroundColor $color }
            else { Write-Host $Message }
        }
    }

    $result = @{ Success = $false; Message = '' }

    try {
        # Try using Microsoft.WinGet.Client module first (modern method)
        & $logWriter 'Attempting installation via Microsoft.WinGet.Client...' 'Info'

        # Install NuGet if needed
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -ForceBootstrap | Out-Null
        }

        # Install WinGet Client module
        if (-not (Get-Module -Name Microsoft.WinGet.Client -ListAvailable)) {
            Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null
        }

        # Repair WinGet using the module
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null

        $result.Success = $true
        $result.Message = 'Installed via Microsoft.WinGet.Client'

    } catch {
        & $logWriter "Microsoft.WinGet.Client method failed: $($_.Exception.Message)" 'Warning'

        # Fallback to manual installation
        try {
            & $logWriter 'Attempting manual installation from GitHub...' 'Info'

            # Download license
            $licenseUrl = Get-WingetDownloadUrl -Match 'License1.xml'
            $licensePath = Join-Path $env:TEMP 'winget_license.xml'
            Invoke-WebRequest -Uri $licenseUrl -OutFile $licensePath -UseBasicParsing

            # Download WinGet
            $wingetUrl = Get-WingetDownloadUrl -Match 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            $wingetPath = Join-Path $env:TEMP 'winget.msixbundle'
            Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath -UseBasicParsing

            # Install
            Add-AppxProvisionedPackage -Online -PackagePath $wingetPath -LicensePath $licensePath | Out-Null

            # Cleanup
            Remove-Item $wingetPath, $licensePath -Force -ErrorAction SilentlyContinue

            $result.Success = $true
            $result.Message = 'Installed via manual GitHub download'

        } catch {
            $result.Message = $_.Exception.Message
        }
    }

    return [PSCustomObject]$result
}

function Register-WinGetPackage {
    <#
    .SYNOPSIS
        Registers WinGet package with the system.
    #>
    [CmdletBinding()]
    param()

    try {
        # Skip registration on Server 2019 or when running as SYSTEM
        $osInfo = Get-OSInfo
        $isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -match 'SYSTEM'

        if ($osInfo.NumericVersion -eq 2019 -or $isSystem) {
            Write-Debug 'Skipping WinGet registration (Server 2019 or SYSTEM context)'
            return
        }

        # Register for current user
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue

        # Fix permissions on Server
        if ($osInfo.Type -eq 'Server') {
            $wingetFolder = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.DesktopAppInstaller*' -Directory -ErrorAction SilentlyContinue |
                            Sort-Object Name -Descending |
                            Select-Object -First 1 -ExpandProperty FullName

            if ($wingetFolder) {
                Set-PathPermission -FolderPath $wingetFolder
                Add-ToEnvironmentPath -PathToAdd $wingetFolder -Scope 'System'
            }
        }

    } catch {
        Write-Debug "Registration failed: $($_.Exception.Message)"
    }
}

function Update-SessionPath {
    <#
    .SYNOPSIS
        Refreshes the PATH environment variable for the current session.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    if (-not $PSCmdlet.ShouldProcess('process PATH variable', 'Refresh session PATH from registry')) {
        return
    }

    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        $env:PATH = "$machinePath;$userPath"

        # Add WindowsApps to user PATH if not present
        $windowsAppsPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$windowsAppsPath*") {
            Add-ToEnvironmentPath -PathToAdd $windowsAppsPath -Scope 'User'
        }

        Write-Debug 'Session PATH refreshed'
    } catch {
        Write-Debug "Failed to refresh PATH: $($_.Exception.Message)"
    }
}

function Initialize-WinGet {
    <#
    .SYNOPSIS
        Ensures WinGet is available and functional, installing if necessary.

    .DESCRIPTION
        Single function to call that guarantees WinGet is ready to use.
        This is the main entry point for scripts that need WinGet.

        After a fresh Windows install, WinGet may take time to become ready.
        This function checks WinGet readiness up to 3 times with 10-second intervals.

    .OUTPUTS
        Hashtable with Path and Version properties.

    .EXAMPLE
        $wg = Initialize-WinGet
        & $wg.Path install --id 7zip.7zip
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $logCommand = Get-Command Write-Log -ErrorAction SilentlyContinue

    # Quick check first
    $wg = Test-WinGet
    if ($wg.IsAvailable) {
        if ($logCommand) {
            Write-Log "WinGet is already available (v$($wg.Version))" -Level Verbose
        }
        return @{ Path = $wg.WinGetPath; Version = $wg.Version }
    }

    # Need to install/repair
    if ($logCommand) {
        Write-Log 'WinGet not available, initiating installation...' -Level Warning
    }

    $repairResult = Repair-WinGet -IncludeDependencies

    if (-not $repairResult.Success) {
        throw "Failed to ensure WinGet: $($repairResult.Message)"
    }

    # After installation, WinGet may need time to become ready (especially on fresh Windows installs)
    # Check up to 3 times with 10-second intervals (30 seconds total)
    if ($logCommand) {
        Write-Log 'Waiting for WinGet to become fully ready...' -Level Info
    }

    $maxAttempts = 3
    $delaySeconds = 10

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        if ($logCommand) {
            Write-Log "Checking WinGet readiness (attempt $attempt of $maxAttempts)..." -Level Verbose
        }

        # Test if WinGet can execute a simple command
        try {
            $testOutput = & $repairResult.WinGetPath --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $testOutput) {
                if ($logCommand) {
                    Write-Log "WinGet is ready (v$($repairResult.Version))" -Level Success
                }
                return @{
                    Path = $repairResult.WinGetPath
                    Version = $repairResult.Version
                }
            }
        } catch {
            if ($logCommand) {
                Write-Log "WinGet not ready yet: $($_.Exception.Message)" -Level Verbose
            }
        }

        if ($attempt -lt $maxAttempts) {
            if ($logCommand) {
                Write-Log "WinGet not ready, waiting $delaySeconds seconds before retry..." -Level Info
            }
            Start-Sleep -Seconds $delaySeconds
        }
    }

    # If still not ready after all attempts, log warning but return the path anyway
    if ($logCommand) {
        Write-Log "WinGet may not be fully ready after $($maxAttempts * $delaySeconds) seconds, but will attempt to use it" -Level Warning
    }

    return @{
        Path = $repairResult.WinGetPath
        Version = $repairResult.Version
    }
}

function Get-WinGetExitCodeDescription {
    <#
    .SYNOPSIS
        Provides a human-readable description for WinGet exit codes.
    .OUTPUTS
        String describing the supplied exit code.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$ExitCode)
    $codes = @{
        0 = "Success"
        -1978335231 = "Internal Error"
        -1978335230 = "Invalid command line arguments"
        -1978335229 = "Executing command failed"
        -1978335226 = "Installer failed"
        -1978335224 = "Downloading installer failed"
        -1978335216 = "No applicable installer"
        -1978335215 = "Installer hash mismatch"
        -1978335212 = "No packages found"
        -1978335210 = "Multiple packages found"
        -1978335207 = "Requires administrator privileges"
        -1978335189 = "Already up-to-date"
        -1978335188 = "Upgrade all completed with failures"
        -1978335174 = "Blocked by Group Policy"
        -1978335135 = "Package already installed"
        -1978334975 = "Application currently running"
        -1978334974 = "Another installation in progress"
        -1978334973 = "File in use"
        -1978334972 = "Missing dependency"
        -1978334971 = "Disk full"
        -1978334970 = "Insufficient memory"
        -1978334969 = "No network connection"
        -1978334967 = "Reboot required to finish"
        -1978334966 = "Reboot required to install"
        -1978334964 = "Cancelled by user"
        -1978334963 = "Another version already installed"
        -1978334962 = "Downgrade attempt"
        -1978334961 = "Blocked by policy"
        -1978334960 = "Failed to install dependencies"
    }
    if ($codes.ContainsKey($ExitCode)) { return $codes[$ExitCode] }
    return "Unknown exit code"
}

function Get-MSIExitCodeDescription {
    <#
    .SYNOPSIS
        Maps MSI exit codes to named constants and descriptions.
    .OUTPUTS
        PSCustomObject containing ExitCode, Name, and Description.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][int]$ExitCode)
    $codes = @{
        0 = @{ Name = "SUCCESS"; Description = "Completed successfully" }
        1602 = @{ Name = "USER_EXIT"; Description = "User cancelled" }
        1603 = @{ Name = "INSTALL_FAILURE"; Description = "Fatal error during installation" }
        1618 = @{ Name = "ALREADY_RUNNING"; Description = "Another installation in progress" }
        1619 = @{ Name = "PACKAGE_OPEN_FAILED"; Description = "Could not open package" }
        1620 = @{ Name = "PACKAGE_INVALID"; Description = "Invalid package" }
        1638 = @{ Name = "PRODUCT_VERSION"; Description = "Another version already installed" }
        1641 = @{ Name = "REBOOT_INITIATED"; Description = "Reboot has started" }
        3010 = @{ Name = "REBOOT_REQUIRED"; Description = "Reboot required to complete" }
    }
    if ($codes.ContainsKey($ExitCode)) {
        return [PSCustomObject]@{
            ExitCode = $ExitCode
            Name = $codes[$ExitCode].Name
            Description = $codes[$ExitCode].Description
        }
    }
    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Name = "UNKNOWN"
        Description = "Unknown exit code"
    }
}

function Install-WinGetDependency {
    <#
    .SYNOPSIS
        Ensures WinGet dependencies are installed and up to date.
    .DESCRIPTION
        Accepts either plain string IDs or hashtables with additional metadata like Source,
        DisplayName, AppxName, PackageFamilyName, FallbackSources, and InstallerUri. Returns
        per-dependency status objects describing the work performed.
    .PARAMETER Dependency
        Dependency identifier (string) or metadata hashtable describing the requirement.
    .PARAMETER WinGetPath
        Optional explicit path to winget.exe. Auto-detected when omitted.
    .PARAMETER Quiet
        Suppresses host output when Write-Log is unavailable.
    .OUTPUTS
        PSCustomObject with Id, DisplayName, Satisfied, Changed, ExitCode, Message, Source, Attempts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Dependency,
        [string]$WinGetPath,
        [switch]$Quiet
    )

    begin {
        $quietRequested = [bool]$Quiet

        if (-not $WinGetPath) {
            $wg = Test-WinGetFunctional
            $WinGetPath = $wg.Path
        }
        $logCommand = Get-Command Write-Log -ErrorAction SilentlyContinue
        $colorMap = @{
            Info = 'Cyan'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Verbose = 'Gray'; Debug = 'Magenta'
        }
        $logWriter = {
            param([string]$Message, [string]$Level)
            if ($logCommand) {
                Write-Log $Message -Level $Level
            } elseif (-not $quietRequested) {
                $color = $colorMap[$Level]
                if ($color) {
                    Write-Host $Message -ForegroundColor $color
                } else {
                    Write-Host $Message
                }
            }
        }
    }

    process {
        if ($null -eq $Dependency) { return }
        if ($Dependency -is [string]) {
            $depInfo = @{ Id = $Dependency }
        } elseif ($Dependency -is [hashtable]) {
            $depInfo = @{}

            foreach ($key in $Dependency.Keys) {
                $depInfo[$key] = $Dependency[$key]
            }
        } else {
            throw "Unsupported dependency type: $($Dependency.GetType().FullName)"
        }

        $id = $depInfo.Id
        $displayName = if ($depInfo.DisplayName) { $depInfo.DisplayName } else { $id }
        $appxName = $depInfo.AppxName
        $familyName = $depInfo.PackageFamilyName

        $sources = @()
        if ($depInfo.Source) { $sources += $depInfo.Source }
        if ($depInfo.FallbackSources) { $sources += @($depInfo.FallbackSources) }
        $sources += $null
        $sources = $sources | Where-Object { $_ -ne '' } | Select-Object -Unique
        if (-not $sources) { $sources = @($null) }

        $satisfied = $false
        $changed = $false
        $exitCode = $null
        $message = $null
        $attemptCount = 0
        $results = @()

        # Detect existing installation via AppX if metadata provided
        # Use Windows PowerShell for Appx commands to avoid assembly conflicts in PS7
        $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7
        if ($appxName) {
            if ($useWindowsPowerShell) {
                $checkScript = "Get-AppxPackage -Name '$appxName' -ErrorAction SilentlyContinue | ConvertTo-Json -Compress"
                $result = powershell.exe -NoProfile -Command $checkScript
                $satisfied = [bool]($result -and $result -ne 'null')
            } else {
                $satisfied = [bool](Get-AppxPackage -Name $appxName -ErrorAction SilentlyContinue)
            }

            # Special handling for UI.Xaml.2.8 - accept any version 2.8 or higher
            if ($satisfied -and $appxName -like '*UI.Xaml.2.8*') {
                if ($useWindowsPowerShell) {
                    $versionCheckScript = "Get-AppxPackage -Name '*UI.Xaml*' | Select-Object -First 1 -ExpandProperty Version"
                    $installedVersion = powershell.exe -NoProfile -Command $versionCheckScript
                } else {
                    $xamlPackage = Get-AppxPackage -Name '*UI.Xaml*' -ErrorAction SilentlyContinue | Select-Object -First 1
                    $installedVersion = $xamlPackage.Version
                }

                if ($installedVersion) {
                    try {
                        $installedVer = [version]$installedVersion
                        $requiredVer = [version]'2.8.0.0'
                        if ($installedVer -ge $requiredVer) {
                            & $logWriter "    UI.Xaml version $installedVersion satisfies requirement (>= 2.8)" 'Verbose'
                            $satisfied = $true
                        } else {
                            & $logWriter "    UI.Xaml version $installedVersion is older than 2.8 - will upgrade" 'Verbose'
                            $satisfied = $false
                        }
                    } catch {
                        & $logWriter "    Could not parse UI.Xaml version - will attempt installation" 'Verbose'
                        $satisfied = $false
                    }
                } else {
                    $satisfied = $false
                }
            }
        }
        if (-not $satisfied -and $familyName) {
            if ($useWindowsPowerShell) {
                $checkScript = "Get-AppxPackage -PackageFamilyName '$familyName' -ErrorAction SilentlyContinue | ConvertTo-Json -Compress"
                $result = powershell.exe -NoProfile -Command $checkScript
                $satisfied = [bool]($result -and $result -ne 'null')
            } else {
                $satisfied = [bool](Get-AppxPackage -PackageFamilyName $familyName -ErrorAction SilentlyContinue)
            }
        }

        # Fallback detection via winget list
        if (-not $satisfied) {
            $listArgs = @('list', '--exact', '--id', $id)
            foreach ($source in $sources) {
                $commandArgs = $listArgs.Clone()
                if ($source) { $commandArgs += @('--source', $source) }
                $listOutput = & $WinGetPath @commandArgs 2>&1
                if ($LASTEXITCODE -eq 0 -and ($listOutput | Select-String $id -SimpleMatch)) {
                    $satisfied = $true
                    break
                }
            }
        }

        if ($satisfied) {
            & $logWriter "[Dependency] $displayName already installed" 'Verbose'
            return [PSCustomObject]@{
                Id = $id
                DisplayName = $displayName
                Satisfied = $true
                Changed = $false
                ExitCode = 0
                Message = 'Already installed'
                Source = $null
                Attempts = 0
            }
        }
        & $logWriter "[Dependency] Installing $displayName..." 'Info'

        foreach ($source in $sources) {
            $attemptCount++
            $commandArgs = @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
            if ($source) { $commandArgs += @('--source', $source) }

            $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("winget_dep_{0}" -f ([guid]::NewGuid()))
            $stdoutFile = "$tempBase.out"
            $stderrFile = "$tempBase.err"

            try {
                $process = Start-Process $WinGetPath -ArgumentList $commandArgs -Wait -PassThru -NoNewWindow `
                    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
                $exitCode = $process.ExitCode
                $message = Get-WinGetExitCodeDescription -ExitCode $exitCode
                $successCodes = @(0, -1978335189, -1978335135, -1978334967, -1978334966)

                if ($exitCode -in $successCodes) {
                    & $logWriter "    ✓ $message" 'Success'
                    $satisfied = $true
                    $changed = $true
                    $results += [pscustomobject]@{
                        Id = $id
                        DisplayName = $displayName
                        Satisfied = $true
                        Changed = $true
                        ExitCode = $exitCode
                        Message = $message
                        Source = $source
                        Attempts = $attemptCount
                    }
                    break
                }

                if ($exitCode -eq -1978335212 -and $sources.Count -gt 1) {
                    & $logWriter "    ↻ $message; trying alternate source..." 'Warning'
                    continue
                }

                & $logWriter "    ✗ $message (exit: $exitCode)" 'Warning'

                $details = @()
                if (Test-Path $stdoutFile) { $details += (Get-Content $stdoutFile -ErrorAction SilentlyContinue) }
                if (Test-Path $stderrFile) { $details += (Get-Content $stderrFile -ErrorAction SilentlyContinue) }
                if ($details) {
                    $lines = $details | Where-Object { $_ }
                    $excerpt = ($lines | Select-Object -First 3) -join ' '
                    if ($excerpt) {
                        & $logWriter ("        Output: {0}" -f ($excerpt -replace '\s{2,}',' ')) 'Verbose'
                    }
                }
            } catch {
                $message = $_.Exception.Message
                $exitCode = -1
                & $logWriter ("    ✗ Exception installing {0}: {1}" -f $displayName, $message) 'Error'
            } finally {
                Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $satisfied -and $depInfo.ContainsKey('InstallerUri')) {
            $attemptCount++
            $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}_{1}" -f ($id -replace '[^\w\-]', '_'), [guid]::NewGuid())
            try {
                & $logWriter "    ↓ Downloading direct package for $displayName" 'Info'
                Invoke-WebRequest -Uri $depInfo.InstallerUri -OutFile $downloadPath -ErrorAction Stop
                Add-AppxPackage -Path $downloadPath -ErrorAction Stop
                $satisfied = $true
                $changed = $true
                $exitCode = 0
                $message = 'Installed via direct package'
                & $logWriter "    ✓ Installed via direct package" 'Success'
            } catch {
                $message = $_.Exception.Message
                $exitCode = -1
                & $logWriter "    ✗ Failed to install $displayName via direct package: $message" 'Error'
            } finally {
                Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $satisfied) {
            & $logWriter "[Dependency] Failed to ensure $displayName" 'Warning'
        }

        $results += [pscustomobject]@{
            Id = $id
            DisplayName = $displayName
            Satisfied = $satisfied
            Changed = $changed
            ExitCode = if ($null -ne $exitCode) { $exitCode } else { 1 }
            Message = if ($message) { $message } else { 'Installation failed' }
            Source = $sources[0]
            Attempts = $attemptCount
        }
    }

    end {
        return $results
    }
}

function Find-WinGet {
    <#
    .SYNOPSIS
        Locates the winget executable on the local system.

    .OUTPUTS
        String. Full path to winget.exe when found; otherwise $null.
    #>
    [CmdletBinding()]
    param()

    try {
        $pathTemplate = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe'
        $resolved = Resolve-Path -Path $pathTemplate -ErrorAction Stop | Sort-Object {
            [version]($_.Path -replace '^[^_]+_((\d+\.)*\d+)_.*', '$1')
        }
        if ($resolved) {
            $installRoot = $resolved[-1].Path
            $candidate = Join-Path $installRoot 'winget.exe'
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    } catch {
        Write-Debug "Find-WinGet failed: $($_.Exception.Message)"
    }

    return $null
}

function Get-OSInfo {
    <#
        .SYNOPSIS
        Retrieves detailed information about the operating system version and architecture.
    #>
    [CmdletBinding()]
    param()

    try {
        $registryValues = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $releaseIdValue = $registryValues.ReleaseId
        $displayVersionValue = $registryValues.DisplayVersion
        $nameValue = $registryValues.ProductName
        $editionIdValue = $registryValues.EditionId -replace 'Server',''

        try {
            $osDetails = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } catch {
            throw "Unable to run Get-CimInstance Win32_OperatingSystem: $($_.Exception.Message)"
        }

        $nameValue = $osDetails.Caption
        # Extract numbers from architecture (e.g., "64-bit" -> "64")
        # Use [^0-9] instead of [\D] or [^\d] for PS 5.1 compatibility
        $architecture = $osDetails.OSArchitecture -replace "[^0-9]", ""
        $architecture = $architecture.Trim()
        if ($architecture -eq '32') { $architecture = 'x32' }
        elseif ($architecture -eq '64') { $architecture = 'x64' }

        $versionValue = [System.Environment]::OSVersion.Version

        if ($osDetails.ProductType -eq 1) { $typeValue = 'Workstation' }
        elseif ($osDetails.ProductType -in 2,3) { $typeValue = 'Server' }
        else { $typeValue = 'Unknown' }

        # Extract numbers from name (e.g., "Windows 11" -> "11")
        # Use [^0-9] instead of [\D] or [^\d] for PS 5.1 compatibility
        $numericVersion = $nameValue -replace "[^0-9]", ""
        $numericVersion = $numericVersion.Trim()
        if ($numericVersion -ge 10 -and $osDetails.Caption -match 'multi-session') {
            $typeValue = 'Workstation'
        }

        return [pscustomobject]@{
            ReleaseId      = $releaseIdValue
            DisplayVersion = $displayVersionValue
            Name           = $nameValue
            Type           = $typeValue
            NumericVersion = $numericVersion
            EditionId      = $editionIdValue
            Version        = $versionValue
            Architecture   = $architecture
        }
    } catch {
        throw "Unable to get OS version details: $($_.Exception.Message)"
    }
}

function CheckForUpdate {
    <#
        .SYNOPSIS
        Placeholder for legacy update-check functionality.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RepoOwner,
        [Parameter(Mandatory)] [string]$RepoName,
        [Parameter(Mandatory)] [version]$CurrentVersion,
        [string]$PowerShellGalleryName
    )

    Write-Warning 'Online update checks are disabled in this environment.'
    Write-Output ("Repository: https://github.com/{0}/{1}" -f $RepoOwner, $RepoName)
    Write-Output ("Current Version:  {0}" -f $CurrentVersion)
    if ($PowerShellGalleryName) {
        Write-Output ("Update manually via PSGallery: Install-Script {0} -Force" -f $PowerShellGalleryName)
    }

    return $null
}

function UpdateSelf {
    <#
        .SYNOPSIS
        Updates the winget installer script from the PowerShell Gallery when a newer version exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [version]$CurrentVersion,
        [Parameter(Mandatory)] [string]$PowerShellGalleryName
    )

    try {
        $psGalleryScript = Find-Script -Name $PowerShellGalleryName -ErrorAction Stop
        if ($CurrentVersion -lt $psGalleryScript.Version) {
            Write-Output "Updating script to version $($psGalleryScript.Version)..."
            $policy = (Get-PSRepository -Name 'PSGallery').InstallationPolicy
            if ($policy -ne 'Trusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted | Out-Null
            }
            Install-Script $PowerShellGalleryName -Force
            if ($policy -ne 'Trusted') {
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy $policy | Out-Null
            }
            Write-Output "Script updated to version $($psGalleryScript.Version)."
            return $true
        }

        Write-Output 'Script is already up to date.'
        return $false
    } catch {
        Write-Output "An error occurred during script update: $($_.Exception.Message)"
        return $false
    }
}

function Write-Section {
    <#
        .SYNOPSIS
        Prints a decorated section header for console readability.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$text)

    Write-Output ''
    Write-Output ('#' * ($text.Length + 4))
    Write-Output "# $text #"
    Write-Output ('#' * ($text.Length + 4))
    Write-Output ''
}

function Get-WingetDownloadUrl {
    <#
        .SYNOPSIS
        Retrieves the download URL for a winget release asset matching a pattern.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Match)

    $uri = 'https://api.github.com/repos/microsoft/winget-cli/releases'
    $releases = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
    foreach ($release in $releases) {
        if ($release.name -match 'preview') { continue }
        $asset = $release.assets | Where-Object name -Match $Match
        if ($asset) { return $asset.browser_download_url }
    }

    $latest = $releases | Select-Object -First 1
    return ($latest.assets | Where-Object name -Match $Match).browser_download_url
}

function Get-WingetStatus {
    <#
        .SYNOPSIS
        Determines whether winget is currently available on the system.
    #>
    [CmdletBinding()]
    param([switch]$RunAsSystem)

    if ($RunAsSystem) {
        $wingetPath = Find-WinGet
        $winget = if ($wingetPath) { & $wingetPath -v } else { $null }
    } else {
        $winget = Get-Command -Name winget -ErrorAction SilentlyContinue
    }

    return ($null -ne $winget -and $winget -notlike '*failed to run*')
}

function Invoke-ErrorHandler {
    <#
        .SYNOPSIS
        Handles common deployment errors encountered during winget installation.
    #>
    [CmdletBinding()]
    param($ErrorRecord)

    $originalPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    try {
        switch -Regex ($ErrorRecord.Exception.Message) {
            '0x80073D06' {
                Write-Warning 'Higher version already installed.'
                Write-Warning "That's okay, continuing..."
                break
            }
            '0x80073CF0' {
                Write-Warning 'Same version already installed.'
                Write-Warning "That's okay, continuing..."
                break
            }
            '0x80073D02' {
                Write-Warning 'Resources modified are in use. Close PowerShell/Terminal windows and try again.'
                Write-Warning 'Consider re-running the script with -ForceClose to terminate conflicting processes.'
                return $ErrorRecord
            }
            '0x80073CF3' {
                Write-Warning 'Problem detected with a prerequisite package.'
                Write-Warning 'Re-run the script or use -ForceClose to retry in a clean session.'
                return $ErrorRecord
            }
            '0x80073CF9' {
                Write-Warning 'Registering winget failed with error code 0x80073CF9.'
                Write-Warning 'Running under the SYSTEM account is not officially supported. Retry as an Administrator.'
                break
            }
            'Unable to connect to the remote server' {
                Write-Warning 'Cannot reach download endpoints. Verify Internet connectivity and try again later.'
                return $ErrorRecord
            }
            'The remote name could not be resolved' {
                Write-Warning 'DNS resolution failed. Check network connectivity before retrying.'
                break
            }
            default { return $ErrorRecord }
        }
    } finally {
        $ErrorActionPreference = $originalPreference
    }

    return $null
}

function Get-CurrentProcess {
    <#
        .SYNOPSIS
        Returns the current PowerShell host process details.
    #>
    [CmdletBinding()]
    param()

    $oldTitle = $host.UI.RawUI.WindowTitle
    $tempTitle = [guid]::NewGuid()
    $host.UI.RawUI.WindowTitle = $tempTitle
    Start-Sleep -Seconds 1
    $proc = Get-Process | Where-Object { $_.MainWindowTitle -eq $tempTitle }
    $host.UI.RawUI.WindowTitle = $oldTitle
    return [pscustomobject]@{ Name = $proc.Name; Id = $proc.Id }
}

function Import-GlobalVariable {
    <#
        .SYNOPSIS
        Imports a global variable into script scope when present.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VariableName)

    try {
        $value = Get-Variable -Name $VariableName -ValueOnly -Scope Global -ErrorAction Stop
        Set-Variable -Name $VariableName -Value $value -Scope Script
        return $true
    } catch {
        return $false
    }
}

function Test-AdminPrivilege {
    <#
        .SYNOPSIS
        Indicates whether the current process runs with administrative rights.
    #>
    [CmdletBinding()]
    param()

    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-TemporaryFile2 {
    <#
        .SYNOPSIS
        Creates a unique temporary file path compatible with Windows PowerShell 5.1.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    $tempPath = [IO.Path]::GetTempPath()
    $tempFile = [IO.Path]::Combine($tempPath, [IO.Path]::GetRandomFileName())

    if (-not $PSCmdlet.ShouldProcess($tempFile, 'Create temporary file')) {
        return $null
    }

    New-Item -Path $tempFile -ItemType File -Force | Out-Null
    return $tempFile
}

function Test-PathInEnvironment {
    <#
        .SYNOPSIS
        Checks whether a path is present in the PATH environment variable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathToCheck,
        [ValidateSet('User','System','Both')][string]$Scope = 'Both'
    )

    $exists = $false
    if ($Scope -in 'User','Both') {
        if (($env:PATH -split ';').Contains($PathToCheck)) { $exists = $true }
    }
    if ($Scope -in 'System','Both') {
        $systemPath = [Environment]::GetEnvironmentVariable('PATH',[EnvironmentVariableTarget]::Machine)
        if (($systemPath -split ';').Contains($PathToCheck)) { $exists = $true }
    }
    return $exists
}

function Add-ToEnvironmentPath {
    <#
        .SYNOPSIS
        Appends a directory to the PATH environment variable if missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathToAdd,
        [Parameter(Mandatory)][ValidateSet('User','System')][string]$Scope
    )

    if (Test-PathInEnvironment -PathToCheck $PathToAdd -Scope $Scope) {
        Write-Debug "$PathToAdd is already present in PATH."
        return
    }

    if ($Scope -eq 'System') {
        $systemPath = [Environment]::GetEnvironmentVariable('PATH',[EnvironmentVariableTarget]::Machine)
        [Environment]::SetEnvironmentVariable('PATH',"$systemPath;$PathToAdd",[EnvironmentVariableTarget]::Machine)
        Write-Debug "Added $PathToAdd to system PATH."
    } else {
        $userPath = [Environment]::GetEnvironmentVariable('PATH',[EnvironmentVariableTarget]::User)
        [Environment]::SetEnvironmentVariable('PATH',"$userPath;$PathToAdd",[EnvironmentVariableTarget]::User)
        Write-Debug "Added $PathToAdd to user PATH."
    }

    if (-not (($env:PATH -split ';').Contains($PathToAdd))) {
        $env:PATH += ";$PathToAdd"
        Write-Debug "Added $PathToAdd to current process PATH."
    }
}

function Set-PathPermission {
    <#
        .SYNOPSIS
        Grants Administrators full control on the specified folder path.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$FolderPath)

    if (-not $PSCmdlet.ShouldProcess($FolderPath, 'Grant Administrators full control')) {
        return
    }

    Write-Debug "Granting Administrators full control on $FolderPath"
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $admins = $adminSid.Translate([System.Security.Principal.NTAccount])
    $acl = Get-Acl -Path $FolderPath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $admins,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $FolderPath -AclObject $acl
}

function Test-VCRedistInstalled {
    <#
        .SYNOPSIS
        Checks whether Visual C++ Redistributable 14 is installed.
    #>
    [CmdletBinding()]
    param()

    $is64Os = [Environment]::Is64BitOperatingSystem
    $is64Process = [Environment]::Is64BitProcess
    if ($is64Os -and -not $is64Process) {
        throw 'Run this check from a native architecture PowerShell process.'
    }

    $regPath = [string]::Format(
        'Registry::HKEY_LOCAL_MACHINE\\SOFTWARE\\{0}Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X{1}',
        $(if ($is64Os -and $is64Process) { 'WOW6432Node' } else { '' }),
        $(if ($is64Os) { '64' } else { '86' })
    )

    $registryExists = Test-Path $regPath
    $majorVersion = if ($registryExists) { (Get-ItemProperty -Path $regPath -Name 'Major').Major } else { 0 }
    $dllPath = Join-Path $env:WINDIR 'system32\concrt140.dll'
    return ($registryExists -and $majorVersion -eq 14 -and (Test-Path $dllPath))
}

function TryRemove {
    <#
        .SYNOPSIS
        Removes a file when it exists, suppressing errors.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath)

    try {
        if (Test-Path $FilePath) {
            Remove-Item -Path $FilePath -ErrorAction SilentlyContinue
            if ($?) { Write-Debug "Removed $FilePath" }
        }
    } catch {
        Write-Debug ("Failed to remove {0}: {1}" -f $FilePath, $_.Exception.Message)
    }
}

function Install-NuGetIfRequired {
    <#
        .SYNOPSIS
        Installs the NuGet PackageProvider when absent.
    #>
    [CmdletBinding()]
    param([switch]$DebugMode)

    if (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue) {
        Write-Debug 'NuGet PackageProvider already installed.'
        return
    }

    Write-Debug 'NuGet PackageProvider not detected.'
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Debug 'Installing NuGet PackageProvider for PowerShell < 7.'
        if ($DebugMode) {
            try {
                Install-PackageProvider -Name NuGet -Force -ForceBootstrap -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "NuGet provider installation failed: $($_.Exception.Message)"
            }
        } else {
            try {
                Install-PackageProvider -Name NuGet -Force -ForceBootstrap -ErrorAction SilentlyContinue | Out-Null
            } catch {
                Write-Warning "NuGet provider installation failed: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Warning 'NuGet is missing in PowerShell 7. Reinstall PowerShell 7 to restore the provider.'
    }
}

function Get-ManifestVersion {
    <#
        .SYNOPSIS
        Reads the AppxManifest version from a dependency package.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Lib_Path)

    Write-Debug "Inspecting manifest in $Lib_Path"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Lib_Path)
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' }
    if (-not $entry) {
        $zip.Dispose()
        throw "AppxManifest.xml not found in $Lib_Path"
    }

    $reader = New-Object IO.StreamReader($entry.Open())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()
    $zip.Dispose()
    return $xml.Package.Identity.Version
}

function Get-InstalledLibVersion {
    <#
        .SYNOPSIS
        Retrieves the installed version for a dependency package.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Lib_Name)

    $pkg = Get-AppxPackage -Name "*$Lib_Name*" -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg) {
        Write-Debug "Installed $Lib_Name version: $($pkg.Version)"
        return $pkg.Version
    }

    Write-Output 'Library is not installed.'
    return $null
}

function Install-LibIfRequired {
    <#
        .SYNOPSIS
        Installs or updates a dependency package when required.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Lib_Name,
        [Parameter(Mandatory)][string]$Lib_Path,
        [switch]$RunAsSystem
    )

    $installedVersion = Get-InstalledLibVersion -Lib_Name $Lib_Name
    $downloadedVersion = Get-ManifestVersion -Lib_Path $Lib_Path

    if ($installedVersion -and $downloadedVersion -le $installedVersion) {
        Write-Output 'Installed library version is up-to-date or newer. Skipping installation.'
        return
    }

    if ($RunAsSystem) {
        Write-Debug 'Installing dependency via provisioning (SYSTEM context).'
        Add-ProvisionedAppxPackage -Online -SkipLicense -PackagePath $Lib_Path | Out-Null
    } else {
        Write-Debug 'Installing dependency for current user.'
        Add-AppxPackage -Path $Lib_Path | Out-Null
    }
}

function New-WinGetInstallArgs {
    <#
    .SYNOPSIS
        Generates standardized WinGet installation argument array.

    .DESCRIPTION
        Creates a consistent argument list for WinGet install commands
        with common parameters like --silent, --accept-agreements, etc.

    .PARAMETER AppId
        The WinGet package ID to install.

    .PARAMETER Force
        Include --force flag to reinstall even if already installed.

    .PARAMETER Source
        Specify a particular source (e.g., 'winget', 'msstore').

    .PARAMETER AdditionalArgs
        Any additional arguments to append.

    .OUTPUTS
        String array suitable for Start-Process -ArgumentList

    .EXAMPLE
        $args = New-WinGetInstallArgs -AppId 'Microsoft.VCLibs.140.00.UWPDesktop'
        Start-Process winget.exe -ArgumentList $args -Wait -NoNewWindow
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Generates parameter list only; no state change occurs.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='Returns a collection of arguments for winget installations.')]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [switch]$Force,

        [string]$Source,

        [string[]]$AdditionalArgs
    )

    $argumentList = @(
        'install',
        '--id', $AppId,
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    if ($Force) {
        $argumentList += '--force'
    }

    if ($Source) {
        $argumentList += '--source', $Source
    }

    if ($AdditionalArgs) {
        $argumentList += $AdditionalArgs
    }

    return $argumentList
}

Export-ModuleMember -Function @(
    'Test-WinGet',
    'Get-WinGetPath',
    'Test-WinGetFunctional',
    'Get-WinGetExitCodeDescription',
    'Get-MSIExitCodeDescription',
    'Install-WinGetDependency',
    'Find-WinGet',
    'Get-OSInfo',
    'CheckForUpdate',
    'UpdateSelf',
    'Write-Section',
    'Get-WingetDownloadUrl',
    'Get-WingetStatus',
    'Invoke-ErrorHandler',
    'Get-CurrentProcess',
    'Import-GlobalVariable',
    'Test-AdminPrivilege',
    'New-TemporaryFile2',
    'Test-PathInEnvironment',
    'Add-ToEnvironmentPath',
    'Set-PathPermission',
    'Test-VCRedistInstalled',
    'TryRemove',
    'Install-NuGetIfRequired',
    'Get-ManifestVersion',
    'Get-InstalledLibVersion',
    'Install-LibIfRequired',
    'Repair-WinGet',
    'Confirm-WinGetDependencyStatus',
    'Install-WinGetSystemPrerequisite',
    'Install-WinGetPackage',
    'Register-WinGetPackage',
    'Update-SessionPath',
    'Initialize-WinGet',
    'New-WinGetInstallArgs'
)
