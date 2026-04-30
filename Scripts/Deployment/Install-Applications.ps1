# ============================================================================
# Install-Applications.ps1
# Installs applications via WinGet package manager.
# Standalone script - can be deployed via any management tool.
# ============================================================================

#requires -Version 5.1
#requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Function Write-DeployLog {
    param([string]$Message, [switch]$IsError)
    $logDir = "C:\WinDeploy\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($MyInvocation.ScriptName))
    $logFile = Join-Path $logDir "$scriptName.log"
    $Message | Out-File -FilePath $logFile -Append
    if ($IsError) { Write-Error $Message } else { Write-Output $Message }
}

try {


    $Applications = @(
        @{Alias="Microsoft.VCRedist.2015+.x64"; Name="Microsoft Visual C++ 2015+ x64 Redistributable"},
        @{Alias="Microsoft.Office"; Name="Microsoft Office"},
        #@{Alias="Adobe.Acrobat.Reader.64-bit"; Name="Adobe Acrobat Reader 64-bit"},
        @{Alias="Microsoft.Teams"; Name="Microsoft Teams"},
        @{Alias="Microsoft.OneDrive"; Name="Microsoft OneDrive"},
        @{Alias="7zip.7zip"; Name="7-Zip"},
        @{Alias="Microsoft.WindowsApp"; Name="Windows App"}
        #@{Alias="Microsoft.CompanyPortal"; Name="Company Portal"} # Problematic package at this moment.
    )

    #Note: Some applications fail to install. This is why we have a separate list for msstore apps.
    $MsStoreApplications = @(
        @{Alias="XP8BT8DW290MPQ"; Name="Microsoft Teams (msstore)"},
        @{Alias="9N1F85V9T8BN"; Name="Windows App (msstore)"},
        @{Alias="9WZDNCRFJ3PZ"; Name="Company Portal (msstore)"},
        @{Alias="9MZ95KL8MR0L"; Name="Screenshot/Recording App (msstore)"}
    )

    # Winget error codes that you may come across during installation. Note that these are not documented all well by Micrsoft. They documenent some of them, but not all.
    # Sometimes we may come across an error, this is why we try to install most apps on 2 ways. Via normal winget and via msstore.
    $WingetErrorDescriptions = @{
        -1978335231 = "Internal Error"
        -1978335230 = "Invalid command line arguments"
        -1978335229 = "Executing command failed"
        -1978335228 = "Opening manifest failed"
        -1978335227 = "Cancellation signal received"
        -1978335226 = "Running ShellExecute failed"
        -1978335225 = "Cannot process manifest. The manifest version is higher than supported. Please update the client."
        -1978335224 = "Downloading installer failed"
        -1978335223 = "Cannot write to index; it is a higher schema version"
        -1978335222 = "The index is corrupt"
        -1978335221 = "The configured source information is corrupt"
        -1978335220 = "The source name is already configured"
        -1978335219 = "The source type is invalid"
        -1978335218 = "The MSIX file is a bundle, not a package"
        -1978335217 = "Data required by the source is missing"
        -1978335216 = "None of the installers are applicable for the current system"
        -1978335215 = "The installer file's hash does not match the manifest"
        -1978335214 = "The source name does not exist"
        -1978335213 = "The source location is already configured under another name"
        -1978335212 = "No packages found"
        -1978335211 = "No sources are configured"
        -1978335210 = "Multiple packages found matching the criteria"
        -1978335209 = "No manifest found matching the criteria"
        -1978335208 = "Failed to get Public folder from source package"
        -1978335207 = "Command requires administrator privileges to run"
        -1978335206 = "The source location is not secure"
        -1978335205 = "The Microsoft Store client is blocked by policy"
        -1978335204 = "The Microsoft Store app is blocked by policy"
        -1978335203 = "The feature is currently under development. It can be enabled using winget settings."
        -1978335202 = "Failed to install the Microsoft Store app"
        -1978335201 = "Failed to perform auto complete"
        -1978335200 = "Failed to initialize YAML parser"
        -1978335199 = "Encountered an invalid YAML key"
        -1978335198 = "Encountered a duplicate YAML key"
        -1978335197 = "Invalid YAML operation"
        -1978335196 = "Failed to build YAML doc"
        -1978335195 = "Invalid YAML emitter state"
        -1978335194 = "Invalid YAML data"
        -1978335193 = "LibYAML error"
        -1978335192 = "Manifest validation succeeded with warning"
        -1978335191 = "Manifest validation failed"
        -1978335190 = "Manifest is invalid"
        -1978335189 = "No applicable update found"
        -1978335188 = "winget upgrade --all completed with failures"
        -1978335187 = "Installer failed security check"
        -1978335186 = "Download size does not match expected content length"
        -1978335185 = "Uninstall command not found"
        -1978335184 = "Running uninstall command failed"
        -1978335183 = "ICU break iterator error"
        -1978335182 = "ICU casemap error"
        -1978335181 = "ICU regex error"
        -1978335180 = "Failed to install one or more imported packages"
        -1978335179 = "Could not find one or more requested packages"
        -1978335178 = "Json file is invalid"
        -1978335177 = "The source location is not remote"
        -1978335176 = "The configured rest source is not supported"
        -1978335175 = "Invalid data returned by rest source"
        -1978335174 = "Operation is blocked by Group Policy"
        -1978335173 = "Rest API internal error"
        -1978335172 = "Invalid rest source url"
        -1978335171 = "Unsupported MIME type returned by rest API"
        -1978335170 = "Invalid rest source contract version"
        -1978335169 = "The source data is corrupted or tampered"
        -1978335168 = "Error reading from the stream"
        -1978335167 = "Package agreements were not agreed to"
        -1978335166 = "Error reading input in prompt"
        -1978335165 = "The search request is not supported by one or more sources"
        -1978335164 = "The rest API endpoint is not found."
        -1978335163 = "Failed to open the source."
        -1978335162 = "Source agreements were not agreed to"
        -1978335161 = "Header size exceeds the allowable limit of 1024 characters. Please reduce the size and try again."
        -1978335160 = "Missing resource file"
        -1978335159 = "Running MSI install failed"
        -1978335158 = "Arguments for msiexec are invalid"
        -1978335157 = "Failed to open one or more sources"
        -1978335156 = "Failed to validate dependencies"
        -1978335155 = "One or more package is missing"
        -1978335154 = "Invalid table column"
        -1978335153 = "The upgrade version is not newer than the installed version"
        -1978335152 = "Upgrade version is unknown and override is not specified"
        -1978335151 = "ICU conversion error"
        -1978335150 = "Failed to install portable package"
        -1978335149 = "Volume does not support reparse points."
        -1978335148 = "Portable package from a different source already exists."
        -1978335147 = "Unable to create symlink, path points to a directory."
        -1978335146 = "The installer cannot be run from an administrator context."
        -1978335145 = "Failed to uninstall portable package"
        -1978335144 = "Failed to validate DisplayVersion values against index."
        -1978335143 = "One or more arguments are not supported."
        -1978335142 = "Embedded null characters are disallowed for SQLite"
        -1978335141 = "Failed to find the nested installer in the archive."
        -1978335140 = "Failed to extract archive."
        -1978335139 = "Invalid relative file path to nested installer provided."
        -1978335138 = "The server certificate did not match any of the expected values."
        -1978335137 = "Install location must be provided."
        -1978335136 = "Archive malware scan failed."
        -1978335135 = "Found at least one version of the package installed."
        -1978335134 = "A pin already exists for the package."
        -1978335133 = "There is no pin for the package."
        -1978335132 = "Unable to open the pin database."
        -1978335131 = "One or more applications failed to install"
        -1978335130 = "One or more applications failed to uninstall"
        -1978335129 = "One or more queries did not return exactly one match"
        -1978335128 = "The package has a pin that prevents upgrade."
        -1978335127 = "The package currently installed is the stub package"
        -1978335126 = "Application shutdown signal received"
        -1978335125 = "Failed to download package dependencies."
        -1978335124 = "Failed to download package. Download for offline installation is prohibited."
        -1978335123 = "A required service is busy or unavailable. Try again later."
        -1978335122 = "The guid provided does not correspond to a valid resume state."
        -1978335121 = "The current client version did not match the client version of the saved state."
        -1978335120 = "The resume state data is invalid."
        -1978335119 = "Unable to open the checkpoint database."
        -1978335118 = "Exceeded max resume limit."
        -1978335117 = "Invalid authentication info."
        -1978335116 = "Authentication method not supported."
        -1978335115 = "Authentication failed."
        -1978335114 = "Authentication failed. Interactive authentication required."
        -1978335113 = "Authentication failed. User cancelled."
        -1978335112 = "Authentication failed. Authenticated account is not the desired account."
        -1978335111 = "Repair command not found."
        -1978335110 = "Repair operation is not applicable."
        -1978335109 = "Repair operation failed."
        -1978335108 = "The installer technology in use doesn't support repair."
        -1978335107 = "Repair operations involving administrator privileges are not permitted on packages installed within the user scope."
        -1978335106 = "The SQLite connection was terminated to prevent corruption."
        -1978335105 = "Failed to get Microsoft Store package catalog."
        -1978335104 = "No applicable Microsoft Store package found from Microsoft Store package catalog."
        -1978335103 = "Failed to get Microsoft Store package download information."
        -1978335102 = "No applicable Microsoft Store package download information found."
        -1978335101 = "Failed to retrieve Microsoft Store package license."
        -1978335100 = "The Microsoft Store package does not support download command."
        -1978335099 = "Failed to retrieve Microsoft Store package license. The Microsoft Entra Id account does not have required privilege."
        -1978335098 = "Downloaded zero byte installer; ensure that your network connection is working properly."
        -1979335097 = "Failed installing one or more fonts."
        -1979335096 = "Font file is not supported and cannot be installed."
        -1979335095 = "Font package is already installed."
        -1979335094 = "Font file not found."
        -1979335093 = "Font uninstall failed. The font may not be in a good state. Try uninstalling after a restart."
        -1979335092 = "Font validation failed."
        -1979335091 = "Font rollback failed. The font may not be in a good state. Try uninstalling after a restart."
        -1978334975 = "Application is currently running. Exit the application then try again."
        -1978334974 = "Another installation is already in progress. Try again later."
        -1978334973 = "One or more file is being used. Exit the application then try again."
        -1978334972 = "This package has a dependency missing from your system."
        -1978334971 = "There's no more space on your PC. Make space, then try again."
        -1978334970 = "There's not enough memory available to install. Close other applications then try again."
        -1978334969 = "This application requires internet connectivity. Connect to a network then try again."
        -1978334968 = "This application encountered an error during installation. Contact support."
        -1978334967 = "Restart your PC to finish installation."
        -1978334966 = "Installation failed. Restart your PC then try again."
        -1978334965 = "Your PC will restart to finish installation."
        -1978334964 = "You cancelled the installation."
        -1978334963 = "Another version of this application is already installed."
        -1978334962 = "A higher version of this application is already installed."
        -1978334961 = "Organization policies are preventing installation. Contact your admin."
        -1978334960 = "Failed to install package dependencies."
        -1978334959 = "Application is currently in use by another application."
        -1978334958 = "Invalid parameter."
        -1978334957 = "Package not supported by the system."
        -1978334956 = "The installer does not support upgrading an existing package."
        -1978334955 = "Installation failed with installer custom error."
        -1978334719 = "The Apps and Features Entry for the package could not be found."
        -1978334718 = "The install location is not applicable."
        -1978334717 = "The install location could not be found."
        -1978334716 = "The hash of the existing file did not match."
        -1978334715 = "File not found."
        -1978334714 = "The file was found but the hash was not checked."
        -1978334713 = "The file could not be accessed."
        -1978286079 = "The configuration file is invalid."
        -1978286078 = "The YAML syntax is invalid."
        -1978286077 = "A configuration field has an invalid type."
        -1978286076 = "The configuration has an unknown version."
        -1978286075 = "An error occurred while applying the configuration."
        -1978286074 = "The configuration contains a duplicate identifier."
        -1978286073 = "The configuration is missing a dependency."
        -1978286072 = "The configuration has an unsatisfied dependency."
        -1978286071 = "An assertion for the configuration unit failed."
        -1978286070 = "The configuration was manually skipped."
        -1978286069 = "A warning was thrown and the user declined to continue execution."
        -1978286068 = "The dependency graph contains a cycle which cannot be resolved."
        -1978286067 = "The configuration has an invalid field value."
        -1978286066 = "The configuration is missing a field."
        -1978286065 = "Some of the configuration units failed while testing their state."
        -1978286064 = "Configuration state was not tested."
        -1978286063 = "The configuration unit failed getting its properties."
        -1978286062 = "The specified configuration could not be found."
        -1978286061 = "Parameter cannot be passed across integrity boundary."
        -1978285823 = "The configuration unit was not installed."
        -1978285822 = "The configuration unit could not be found."
        -1978285821 = "Multiple matches were found for the configuration unit specify the module to select the correct one."
        -1978285820 = "The configuration unit failed while attempting to get the current system state."
        -1978285819 = "The configuration unit failed while attempting to test the current system state."
        -1978285818 = "The configuration unit failed while attempting to apply the desired state."
        -1978285817 = "The module for the configuration unit is available in multiple locations with the same version."
        -1978285816 = "Loading the module for the configuration unit failed."
        -1978285815 = "The configuration unit returned an unexpected result during execution."
        -1978285814 = "A unit contains a setting that requires the config root."
        -1978285813 = "Loading the module for the configuration unit failed because it requires administrator privileges to run."
        -1978285812 = "Operation is not supported by the configuration processor."
        -2147024894 = "The application failed to initialize properly (0x80070646). This indicates a problem with the application's initialization, such as missing or corrupted dependencies, incorrect permissions, or issues with the Windows App Installer package."
    }

    $OfficeFailed = $false

    foreach ($app in $Applications) {
        $alias = $app.Alias
        $name = $app.Name
        # Improved Office detection
        if ($alias -eq "Microsoft.Office") {
            $officeDetected = $false
            # Check known Office registry paths first
            $officeRegPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
                "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot"
            )
            foreach ($regPath in $officeRegPaths) {
                if (Test-Path $regPath) {
                    $officeDetected = $true
                    break
                }
            }
            # Search Uninstall keys for Office products (avoid Win32_Product - it hangs)
            if (-not $officeDetected) {
                $uninstallRoots = @(
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
                )
                foreach ($root in $uninstallRoots) {
                    if (Test-Path $root) {
                        $keys = Get-ChildItem $root -ErrorAction SilentlyContinue
                        foreach ($key in $keys) {
                            $displayName = $key.GetValue("DisplayName")
                            if ($displayName -match "Microsoft Office|Microsoft 365") {
                                $officeDetected = $true
                                break
                            }
                        }
                    }
                    if ($officeDetected) { break }
                }
            }
            if ($officeDetected) {
                Write-DeployLog "Office/M365 already detected on system. Skipping $name ($alias) installation."
                continue
            }
        }
        Write-DeployLog "Installing $name ($alias)..."
        try {
            $output = & winget install --id $alias --source winget --accept-package-agreements --accept-source-agreements 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0 -or $output -match "already installed|No available upgrade") {
                Write-DeployLog "Installed $name ($alias)"
            } else {
                $description = $WingetErrorDescriptions[$exitCode]
                if ($description) {
                    Write-DeployLog "Failed to install $name ($alias) - $description (exit code $exitCode)" -IsError
                } else {
                    Write-DeployLog "Failed to install $name ($alias) (exit code $exitCode)" -IsError
                }
                if ($alias -eq "Microsoft.Office") {
                    $OfficeFailed = $true
                }
            }
        } catch {
            Write-DeployLog "Failed to install $name ($alias)" -IsError
            if ($alias -eq "Microsoft.Office") {
                $OfficeFailed = $true
            }
        }
    }

    if ($OfficeFailed) {
        Write-DeployLog "Winget failed to install Microsoft Office. Attempting direct download from CDN with custom configuration..."
        $setupUrl = "https://officecdn.microsoft.com/pr/wsus/setup.exe"
        $setupPath = Join-Path $env:TEMP "OfficeSetup.exe"
        $configPath = Join-Path $env:TEMP "OfficeConfig.xml"
        try {
            Invoke-WebRequest -Uri $setupUrl -OutFile $setupPath -UseBasicParsing
            Write-DeployLog "Downloaded Office setup to $setupPath"

            # Create config.xml for Dutch M365 Apps. Note that we exclude old, legacy apps like Groove and Lync. Microsoft is deprecating these apps.
            $configContent = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="nl-NL" />
      <Language ID="en-US" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" />
  <Display Level="Full" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
'@
            $configContent | Out-File -FilePath $configPath -Encoding UTF8
            Write-DeployLog "Created Office configuration file at $configPath"

            # Run installation with configuration
            $output = & $setupPath /configure $configPath 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                Write-DeployLog "Office installation completed from direct link with custom configuration."
            } else {
                Write-DeployLog "Office installation failed with exit code $exitCode. Output: $output" -IsError
            }

            # Clean up
            Remove-Item $setupPath, $configPath -Force -ErrorAction SilentlyContinue
            Write-DeployLog "Cleaned up temporary files."
        } catch {
            Write-DeployLog "Failed to install Office from direct link: $($_.Exception.Message)" -IsError
            # Clean up on error
            if (Test-Path $setupPath) { Remove-Item $setupPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path $configPath) { Remove-Item $configPath -Force -ErrorAction SilentlyContinue }
        }
    }

    Write-DeployLog "Installing Microsoft Store versions of the applications listed above..."
    foreach ($app in $MsStoreApplications) {
        $alias = $app.Alias
        $name = $app.Name
        Write-DeployLog "Installing msstore $name ($alias)..."
        try {
            $output = & winget install --id $alias --source msstore --accept-package-agreements --accept-source-agreements 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0 -or $output -match "already installed|No available upgrade") {
                Write-DeployLog "Installed msstore $name ($alias)"
            } else {
                $description = $WingetErrorDescriptions[$exitCode]
                if ($description) {
                    Write-DeployLog "Failed to install msstore $name ($alias) - $description (exit code $exitCode)" -IsError
                } else {
                    Write-DeployLog "Failed to install msstore $name ($alias) (exit code $exitCode)" -IsError
                }
            }
        } catch {
            Write-DeployLog "Failed to install msstore $name ($alias)" -IsError
        }
    }

    Write-DeployLog "SUCCESS: Application installation done."
    exit 0
} catch {
    Write-DeployLog "Error: $($_.Exception.Message)" -IsError
    Write-Error "Application installation partial - continuing."
    exit 0
}
