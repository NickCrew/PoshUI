#Requires -Version 7.6

<#
.SYNOPSIS
    Installs the PoshUI PowerShell module for the current user.

.DESCRIPTION
    Installs, reports, or removes the current-user PoshUI module.
    Installation stages the payload, validates it by importing the staged
    manifest in a clean pwsh process, then atomically replaces the installed
    module. A failed install leaves the previous version in place.

    The installed folder uses the standard PoshUI/<version> module layout.
    Only the runtime module, its manifest, documentation, and feature modules
    are installed.

    By default, the first user-owned entry in PSModulePath is used.

.PARAMETER Action
    Module operation: Install, Status, or Uninstall. Defaults to Install.

.PARAMETER DestinationRoot
    Module root where the PoshUI folder should be installed. Defaults to
    POSH_UI_MODULE_INSTALL_ROOT, then the first user-owned PSModulePath
    entry.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.String

    Status text for -Action Status. Install and Uninstall write progress to
    the information stream.

.EXAMPLE
    PS> ./powershell/tools/Install-PoshUIModule.ps1

    Installs the PoshUI module into the current user's module path.

.EXAMPLE
    PS> ./powershell/tools/Install-PoshUIModule.ps1 -DestinationRoot ./tmp/modules

    Installs the PoshUI module into a custom module root.

.EXAMPLE
    PS> ./powershell/tools/Install-PoshUIModule.ps1 -Action Status

    Reports the installed version and path.

.NOTES
    Version: 1.0.0
    Requires PowerShell 7.6 or later. Windows PowerShell is not supported.

    Adapted from tools/Install-EveModule.ps1 in the eve-powershell repository,
    which is where the staging, canonical-path, and rollback logic came from.

    This repository helper installs or removes the version declared in the
    source manifest.

.LINK
    about_PSModulePath
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([string])]
param(
    [ValidateSet('Install', 'Status', 'Uninstall')]
    [string]$Action = 'Install',

    [string]$DestinationRoot = $env:POSH_UI_MODULE_INSTALL_ROOT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PathSeparators = [char[]]@(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)

$script:ModuleName = 'PoshUI'

# The module manifest sits at the root of powershell/, so that directory is
# the source module folder. tools/ is one level below it.
$script:SourceRoot = Split-Path -Parent $PSScriptRoot

# Explicit runtime payload rather than a recursive copy of $script:SourceRoot.
# Repository tools, tests, examples, and the CLI are intentionally excluded.
$script:InstallPayload = @(
    'PoshUI.psd1'
    'PoshUI.psm1'
    'README.md'
    'modules'
)
$script:ModuleVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $script:SourceRoot 'PoshUI.psd1')).ModuleVersion

function Resolve-PoshUICanonicalPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$LinkDepth = 0
    )

    if ($LinkDepth -gt 64) {
        throw "Cannot resolve path because it contains a circular or excessively deep filesystem link: $Path"
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Cannot resolve the filesystem root for path: $Path"
    }

    $relativePath = $fullPath.Substring($root.Length)
    $segments = $relativePath.Split(
        $script:PathSeparators,
        [StringSplitOptions]::RemoveEmptyEntries
    )
    $resolved = $root

    # Resolve each existing segment so a symlink or junction cannot conceal an
    # escape through a path whose final child is not created yet.
    foreach ($segment in $segments) {
        $next = Join-Path $resolved $segment
        $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            $linkTarget = if ($item.PSObject.Methods.Name -contains 'ResolveLinkTarget') {
                $item.ResolveLinkTarget($true)
            }
            elseif ($item.PSObject.Properties.Name -contains 'Target' -and $item.Target) {
                $targetPath = [string]@($item.Target)[0]
                if (-not [IO.Path]::IsPathRooted($targetPath)) {
                    $linkParent = if ($item -is [IO.DirectoryInfo]) {
                        $item.Parent.FullName
                    }
                    else {
                        $item.DirectoryName
                    }
                    $targetPath = Join-Path $linkParent $targetPath
                }
                [IO.DirectoryInfo]::new(
                    (Resolve-PoshUICanonicalPath -Path $targetPath -LinkDepth ($LinkDepth + 1))
                )
            }
            else {
                $null
            }
            if (
                $item.LinkType -and
                ($null -eq $linkTarget -or -not $linkTarget.Exists)
            ) {
                throw "Cannot resolve filesystem link target: $($item.FullName)"
            }
            $resolved = if ($null -ne $linkTarget) {
                $linkTarget.FullName
            }
            else {
                $item.FullName
            }
        }
        else {
            $nextParent = Split-Path -Parent $next
            $nextLeaf = Split-Path -Leaf $next
            $brokenLink = Get-ChildItem -LiteralPath $nextParent -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $nextLeaf -and $_.LinkType } |
                Select-Object -First 1
            if ($null -ne $brokenLink) {
                throw "Cannot resolve filesystem link target: $($brokenLink.FullName)"
            }
            $resolved = $next
        }
    }

    [IO.Path]::GetFullPath($resolved)
}

function Test-PoshUIPathContained {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Candidate,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $candidatePath = Resolve-PoshUICanonicalPath -Path $Candidate
    $rootPath = Resolve-PoshUICanonicalPath -Path $Root
    $comparison = if ($IsWindows -or $IsMacOS) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }

    if ($candidatePath.Equals($rootPath, $comparison)) {
        return $true
    }

    $rootWithSeparator = $rootPath.TrimEnd(
        $script:PathSeparators
    ) + [IO.Path]::DirectorySeparatorChar
    $candidatePath.StartsWith($rootWithSeparator, $comparison)
}

function Test-PoshUIModuleRootDiscoverable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    $rootPath = Resolve-PoshUICanonicalPath -Path $ModuleRoot
    $comparison = if ($IsWindows -or $IsMacOS) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }

    foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }
        # An entry this user cannot resolve is not a match, and not a reason
        # to fail: PSModulePath routinely carries unresolvable entries.
        try {
            $entryPath = Resolve-PoshUICanonicalPath -Path $entry
        }
        catch {
            Write-Verbose "Skipping unresolvable PSModulePath entry '$entry': $($_.Exception.Message)"
            continue
        }
        if ($entryPath.TrimEnd($script:PathSeparators).Equals(
                $rootPath.TrimEnd($script:PathSeparators), $comparison)) {
            return $true
        }
    }

    $false
}

function Get-DefaultModuleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $homePath = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        $homePath = $HOME
    }
    $homePath = Resolve-PoshUICanonicalPath -Path $homePath

    $modulePaths = ($env:PSModulePath -split [IO.Path]::PathSeparator) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($path in $modulePaths) {
        # An entry that cannot be resolved is skipped rather than fatal.
        # Failing closed is right for the directory being installed into, and
        # wrong while surveying candidates: PSModulePath routinely carries
        # entries pointing at things this user cannot resolve.
        try {
            $contained = Test-PoshUIPathContained -Candidate $path -Root $homePath
        }
        catch {
            Write-Verbose "Skipping unresolvable PSModulePath entry '$path': $($_.Exception.Message)"
            continue
        }
        if ($contained) {
            return Resolve-PoshUICanonicalPath -Path $path
        }
    }

    if ($IsWindows) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documents)) {
            $documents = Join-Path $homePath 'Documents'
        }
        return Join-Path $documents 'PowerShell/Modules'
    }

    Join-Path $homePath '.local/share/powershell/Modules'
}

function Copy-PoshUIPayload {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$SourceModule,

        [Parameter(Mandatory)]
        [string]$StagingModule
    )

    [void](New-Item -ItemType Directory -Path $StagingModule -Force)

    foreach ($entry in $script:InstallPayload) {
        $source = Join-Path $SourceModule $entry
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Cannot stage the $($script:ModuleName) module: payload entry '$entry' is missing from $SourceModule."
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $StagingModule $entry) -Recurse -Force
    }
}

function Test-PoshUIStagedModule {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $pwshName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $pwshPath = Join-Path $PSHOME $pwshName
    if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
        $currentProcessPath = (Get-Process -Id $PID).Path
        if (Test-Path -LiteralPath $currentProcessPath -PathType Leaf) {
            $pwshPath = $currentProcessPath
        }
        else {
            $pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
            $pwshPath = $pwshCommand.Path
        }
    }

    # POSH_UI_LOAD_* toggles are inherited env vars. Left in place, a
    # caller who had turned modules off would validate a partial import and
    # call it good. Clear the whole namespace first, the way Invoke-Tests.ps1
    # does, so validation always exercises a full load.
    $validationScript = @'
try {
    $ErrorActionPreference = "Stop"
    Get-ChildItem Env: |
        Where-Object { $_.Name -like "POSH_UI_*" -and $_.Name -ne "POSH_UI_STAGED_MODULE_MANIFEST" } |
        ForEach-Object { Remove-Item -LiteralPath ("Env:{0}" -f $_.Name) }

    $manifest = $env:POSH_UI_STAGED_MODULE_MANIFEST
    $moduleName = [IO.Path]::GetFileNameWithoutExtension($manifest)
    Import-Module -Name $manifest -Force -ErrorAction Stop
    $commands = @(Get-Command -Module $moduleName)
    if ($commands.Count -eq 0) {
        throw "The staged $moduleName module exported no commands."
    }
    if (-not ($commands.Name -contains "Get-PoshUIConfiguration")) {
        throw "The staged $moduleName module did not export Get-PoshUIConfiguration."
    }
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
'@
    $previousManifest = $env:POSH_UI_STAGED_MODULE_MANIFEST
    try {
        $env:POSH_UI_STAGED_MODULE_MANIFEST = $ManifestPath
        $validationOutput = & $pwshPath -NoLogo -NoProfile -NonInteractive -Command $validationScript 2>&1
    }
    finally {
        if ($null -eq $previousManifest) {
            Remove-Item Env:POSH_UI_STAGED_MODULE_MANIFEST -ErrorAction SilentlyContinue
        }
        else {
            $env:POSH_UI_STAGED_MODULE_MANIFEST = $previousManifest
        }
    }
    if ($LASTEXITCODE -ne 0) {
        $detail = ($validationOutput -join [Environment]::NewLine).Trim()
        throw "The staged $($script:ModuleName) module failed clean-process import validation: $detail"
    }
}

function Invoke-PoshUIModuleInstall {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SourceModule,

        [Parameter(Mandatory)]
        [string]$ModuleRoot,

        [string]$ModuleName = $script:ModuleName
    )

    $moduleDirectory = Join-Path $ModuleRoot $ModuleName
    $destinationModule = Join-Path $moduleDirectory $script:ModuleVersion

    # The source tree and the destination cannot overlap. Without this, a
    # -DestinationRoot pointing at the repository would stage a copy of the
    # source into itself and then move the source aside as the "backup".
    # Checked before anything is created, so a refused install leaves no
    # directories behind.
    if (Test-PoshUIPathContained -Candidate $destinationModule -Root $SourceModule) {
        throw "Refusing to install into '$destinationModule' because it is inside the source module '$SourceModule'."
    }
    if (Test-PoshUIPathContained -Candidate $SourceModule -Root $moduleDirectory) {
        throw "Refusing to install into '$moduleDirectory' because the source module '$SourceModule' is inside it."
    }

    [void](New-Item -ItemType Directory -Path $moduleDirectory -Force)

    $staleCutoff = [DateTime]::UtcNow.AddDays(-1)
    $staleStages = @(
        Get-ChildItem -LiteralPath $moduleDirectory -Directory -Filter ".$ModuleName.stage.*" -Force |
            Where-Object { $_.LastWriteTimeUtc -lt $staleCutoff }
    )
    foreach ($staleStage in $staleStages) {
        Remove-Item -LiteralPath $staleStage.FullName -Recurse -Force
    }

    $staleBackups = @(
        Get-ChildItem -LiteralPath $moduleDirectory -Directory -Filter ".$ModuleName.backup.*" -Force |
            Where-Object { $_.LastWriteTimeUtc -lt $staleCutoff } |
            Sort-Object LastWriteTimeUtc -Descending
    )
    if (
        -not (Test-Path -LiteralPath $destinationModule) -and
        $staleBackups.Count -gt 0
    ) {
        $recoveryBackup = $staleBackups[0]
        Move-Item -LiteralPath $recoveryBackup.FullName -Destination $destinationModule
        Write-Warning "Recovered the previous $ModuleName module from interrupted install backup $($recoveryBackup.FullName)."
        $staleBackups = @($staleBackups | Select-Object -Skip 1)
    }
    foreach ($staleBackup in $staleBackups) {
        Remove-Item -LiteralPath $staleBackup.FullName -Recurse -Force
    }

    $operationId = [Guid]::NewGuid().ToString('N')
    $stagingModule = Join-Path $moduleDirectory ".$ModuleName.stage.$operationId"
    $backupModule = Join-Path $moduleDirectory ".$ModuleName.backup.$operationId"
    $priorInstallMoved = $false
    $promotionComplete = $false

    try {
        Copy-PoshUIPayload -SourceModule $SourceModule -StagingModule $stagingModule
        $stagedManifest = Join-Path $stagingModule "$ModuleName.psd1"
        Test-PoshUIStagedModule -ManifestPath $stagedManifest

        if (Test-Path -LiteralPath $destinationModule) {
            Move-Item -LiteralPath $destinationModule -Destination $backupModule
            $priorInstallMoved = $true
        }

        try {
            Move-Item -LiteralPath $stagingModule -Destination $destinationModule
            $promotionComplete = $true
        }
        catch {
            $promotionError = $_
            if (
                $priorInstallMoved -and
                -not (Test-Path -LiteralPath $destinationModule) -and
                (Test-Path -LiteralPath $backupModule)
            ) {
                try {
                    Move-Item -LiteralPath $backupModule -Destination $destinationModule
                    $priorInstallMoved = $false
                }
                catch {
                    throw (
                        "$ModuleName module promotion and rollback failed. " +
                        "The previous module remains at '$backupModule'. " +
                        "Promotion error: $($promotionError.Exception.Message) " +
                        "Rollback error: $($_.Exception.Message)"
                    )
                }
            }
            elseif ($priorInstallMoved -and (Test-Path -LiteralPath $backupModule)) {
                throw (
                    "$ModuleName module promotion failed and the destination could not be restored automatically. " +
                    "The previous module remains at '$backupModule'. " +
                    "Promotion error: $($promotionError.Exception.Message)"
                )
            }
            throw $promotionError
        }

        if ($priorInstallMoved -and (Test-Path -LiteralPath $backupModule)) {
            Remove-Item -LiteralPath $backupModule -Recurse -Force
            $priorInstallMoved = $false
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingModule) {
            Remove-Item -LiteralPath $stagingModule -Recurse -Force
        }
        if (
            $promotionComplete -and
            (Test-Path -LiteralPath $backupModule)
        ) {
            Remove-Item -LiteralPath $backupModule -Recurse -Force
        }
    }

    $destinationModule
}

foreach ($entry in @('PoshUI.psd1', 'PoshUI.psm1', 'modules')) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:SourceRoot $entry))) {
        throw "Cannot find the $($script:ModuleName) source module at $($script:SourceRoot): '$entry' is missing."
    }
}

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Get-DefaultModuleRoot
}
$DestinationRoot = Resolve-PoshUICanonicalPath -Path $DestinationRoot
$destinationModule = Join-Path (Join-Path $DestinationRoot $script:ModuleName) $script:ModuleVersion

switch ($Action) {
    'Install' {
        if ($PSCmdlet.ShouldProcess($destinationModule, "Install $($script:ModuleName) PowerShell module")) {
            $installedModule = Invoke-PoshUIModuleInstall `
                -SourceModule $script:SourceRoot `
                -ModuleRoot $DestinationRoot

            Write-Information "Installed $($script:ModuleName) module to $installedModule" -InformationAction Continue

            # PSModulePath is searched one level deep, so the destination root
            # has to be an entry itself for `Import-Module PoshUI` to
            # resolve by name. A custom -DestinationRoot usually is not.
            if (-not (Test-PoshUIModuleRootDiscoverable -ModuleRoot $DestinationRoot)) {
                Write-Warning "$DestinationRoot is not on PSModulePath. Import the manifest by path, or add the root to PSModulePath."
                Write-Information "Next: Import-Module $installedModule/$($script:ModuleName).psd1 -Force" -InformationAction Continue
            }
            else {
                Write-Information "Next: Import-Module $($script:ModuleName) -Force" -InformationAction Continue
            }
        }
    }
    'Status' {
        $installedManifest = Join-Path $destinationModule "$($script:ModuleName).psd1"
        if (Test-Path -LiteralPath $installedManifest -PathType Leaf) {
            $manifestData = Test-ModuleManifest -Path $installedManifest -ErrorAction Stop
            Write-Output 'Status:  Installed'
            Write-Output "Version: $($manifestData.Version)"
            Write-Output "Path:    $destinationModule"
        }
        else {
            Write-Output 'Status:  Not installed'
            Write-Output "Path:    $destinationModule"
        }
    }
    'Uninstall' {
        if (-not (Test-Path -LiteralPath $destinationModule)) {
            Write-Information "$($script:ModuleName) module is not installed at $destinationModule" -InformationAction Continue
        }
        elseif ($PSCmdlet.ShouldProcess($destinationModule, "Uninstall $($script:ModuleName) PowerShell module")) {
            Remove-Item -LiteralPath $destinationModule -Recurse -Force
            $moduleDirectory = Split-Path -Parent $destinationModule
            if (-not (Get-ChildItem -LiteralPath $moduleDirectory -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $moduleDirectory -Force
            }
            Write-Information "Removed $($script:ModuleName) module from $destinationModule" -InformationAction Continue
        }
    }
}
