#Requires -Version 7.6

<#
.SYNOPSIS
    Runs repository build, test, documentation, and release-support tasks.

.DESCRIPTION
    Provides the PowerShell-native task graph for PoshUI. Tasks run from the
    repository root, resolve their declared dependencies once, and stop at the
    first failure. The Makefile delegates to this script for command discovery
    and compatibility with existing make targets. This script does not install
    or select a PowerShell runtime. Child tasks reuse the current executable.

.PARAMETER Task
    Task to run. Defaults to help. Task names are case-insensitive.

.PARAMETER OutputPath
    Optional JUnit output path passed to the test task. A relative path is
    resolved from the caller's working directory.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    Task-specific output. Most validation tasks write status to the host.

.EXAMPLE
    PS> ./build.ps1

    Lists the available tasks.

.EXAMPLE
    PS> ./build.ps1 -Task check

    Installs the pinned development modules, then runs all local verification.

.EXAMPLE
    PS> ./build.ps1 -Task test -OutputPath ./test-results-pester.xml

    Runs the Pester suite and writes a JUnit report.

.EXAMPLE
    PS> ./build.ps1 -Task release-plan

    Shows the semantic version implied by commits since the last release tag.

.NOTES
    Requires the environment's PowerShell 7.6 or later. Install and mutation
    tasks support PowerShell's common -WhatIf parameter.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet(
        'help',
        'install',
        'lint',
        'version-check',
        'manifest-check',
        'build',
        'docs',
        'docs-check',
        'test',
        'check',
        'ci',
        'release-plan',
        'release-apply',
        'install-local',
        'clean'
    )]
    [string]$Task = 'help',

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = $PSScriptRoot
$script:PowerShellPath = [Environment]::ProcessPath
if ([string]::IsNullOrWhiteSpace($script:PowerShellPath)) {
    throw 'Cannot resolve the current PowerShell executable.'
}

if ($OutputPath) {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath, (Get-Location).Path)
}

function Invoke-BuildPowerShellFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$ArgumentList = @()
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    & $script:PowerShellPath `
        -NoLogo `
        -NoProfile `
        -NonInteractive `
        -File $resolvedPath `
        @ArgumentList

    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell task file failed with exit code $LASTEXITCODE`: $resolvedPath"
    }
}

function Install-BuildDependency {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $installed = Get-Module -ListAvailable -Name $Name |
        Where-Object Version -EQ $Version
    if ($installed) {
        return
    }

    $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
    if ($repository.InstallationPolicy -ne 'Trusted' -and
        $PSCmdlet.ShouldProcess('PSGallery', 'Set repository installation policy to Trusted')) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    if ($PSCmdlet.ShouldProcess("$Name $Version", 'Install CurrentUser PowerShell module')) {
        Install-Module `
            -Name $Name `
            -RequiredVersion $Version `
            -Scope CurrentUser `
            -Force
    }
}

function Invoke-BuildInstall {
    foreach ($dependency in @(
        @{ Name = 'Pester'; Version = [version]'6.0.1' }
        @{ Name = 'PSScriptAnalyzer'; Version = [version]'1.25.0' }
    )) {
        Install-BuildDependency `
            -Name $dependency.Name `
            -Version $dependency.Version `
            -WhatIf:$WhatIfPreference
    }
}

function Invoke-BuildLint {
    Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop

    $finding = @(
        foreach ($path in @('powershell', 'tools', 'build.ps1')) {
            Invoke-ScriptAnalyzer `
                -Path (Join-Path $script:RepositoryRoot $path) `
                -Recurse `
                -Settings (Join-Path $script:RepositoryRoot 'PSScriptAnalyzerSettings.psd1')
        }
    )

    $finding | Format-Table -AutoSize
    if ($finding.Count -gt 0) {
        throw "PSScriptAnalyzer reported $($finding.Count) finding(s)."
    }
}

function Invoke-BuildVersionCheck {
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'tools/Set-Version.ps1') -ArgumentList '-Check'
}

function Invoke-BuildManifestCheck {
    $manifestPath = Join-Path $script:RepositoryRoot 'powershell/PoshUI.psd1'
    Test-ModuleManifest -Path $manifestPath | Out-Null
    Import-Module $manifestPath -Force -ErrorAction Stop
}

function Invoke-BuildDocumentation {
    $argument = if ($WhatIfPreference) { @('-WhatIf') } else { @() }
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'tools/Update-Docs.ps1') -ArgumentList $argument
}

function Invoke-BuildDocsCheck {
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'tools/Update-Docs.ps1') -ArgumentList '-Check'
}

function Invoke-BuildTest {
    $argument = @()
    if ($OutputPath) {
        $argument += @('-OutputPath', $OutputPath)
    }
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'powershell/tests/Invoke-Tests.ps1') -ArgumentList $argument
}

function Invoke-BuildReleasePlan {
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'tools/Get-NextVersion.ps1') -ArgumentList '-AsObject'
}

function Invoke-BuildReleaseApply {
    $argument = @('-Apply')
    if ($WhatIfPreference) {
        $argument += '-WhatIf'
    }
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'tools/Get-NextVersion.ps1') -ArgumentList $argument
}

function Invoke-BuildInstallLocal {
    $argument = if ($WhatIfPreference) { @('-WhatIf') } else { @() }
    Invoke-BuildPowerShellFile -Path (Join-Path $script:RepositoryRoot 'powershell/tools/Install-PoshUIModule.ps1') -ArgumentList $argument
}

function Invoke-BuildClean {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    foreach ($path in @(
        (Join-Path $script:RepositoryRoot 'test-results-pester.xml')
        (Join-Path $script:RepositoryRoot 'dist')
    )) {
        if ((Test-Path -LiteralPath $path) -and
            $PSCmdlet.ShouldProcess($path, 'Remove generated build output')) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$script:TaskDefinition = [ordered]@{
    'help'           = @{
        Description = 'Show available tasks'
        DependsOn   = @()
        Action      = $null
    }
    'install'        = @{
        Description = 'Install the pinned PowerShell development modules'
        DependsOn   = @()
        Action      = { Invoke-BuildInstall }
    }
    'lint'           = @{
        Description = 'Run PSScriptAnalyzer with the repository policy'
        DependsOn   = @('install')
        Action      = { Invoke-BuildLint }
    }
    'version-check'  = @{
        Description = 'Verify every generated version site matches the manifest'
        DependsOn   = @()
        Action      = { Invoke-BuildVersionCheck }
    }
    'manifest-check' = @{
        Description = 'Validate and import the module manifest'
        DependsOn   = @()
        Action      = { Invoke-BuildManifestCheck }
    }
    'build'          = @{
        Description = 'Validate the publishable module and its generated version sites'
        DependsOn   = @('version-check', 'manifest-check')
        Action      = $null
    }
    'docs'           = @{
        Description = 'Regenerate the PowerShell command reference'
        DependsOn   = @()
        Action      = { Invoke-BuildDocumentation }
    }
    'docs-check'     = @{
        Description = 'Verify the generated command reference is current'
        DependsOn   = @()
        Action      = { Invoke-BuildDocsCheck }
    }
    'test'           = @{
        Description = 'Run the Pester suite'
        DependsOn   = @('install')
        Action      = { Invoke-BuildTest }
    }
    'check'          = @{
        Description = 'Run lint, version, manifest, documentation, and test checks'
        DependsOn   = @('lint', 'build', 'docs-check', 'test')
        Action      = $null
    }
    'ci'             = @{
        Description = 'Run the same verification suite expected before merge'
        DependsOn   = @('check')
        Action      = $null
    }
    'release-plan'   = @{
        Description = 'Show the semantic version implied by commits since the last tag'
        DependsOn   = @()
        Action      = { Invoke-BuildReleasePlan }
    }
    'release-apply'  = @{
        Description = 'Apply the semantic version and roll its changelog section'
        DependsOn   = @()
        Action      = { Invoke-BuildReleaseApply }
    }
    'install-local'  = @{
        Description = "Install PoshUI into the current user's PowerShell module path"
        DependsOn   = @()
        Action      = { Invoke-BuildInstallLocal }
    }
    'clean'          = @{
        Description = 'Remove generated local test and package output'
        DependsOn   = @()
        Action      = { Invoke-BuildClean }
    }
}

function Show-BuildHelp {
    Write-Host 'Usage: pwsh ./build.ps1 -Task <task>'
    Write-Host ''
    Write-Host 'Tasks:'
    foreach ($entry in $script:TaskDefinition.GetEnumerator()) {
        Write-Host ('  {0,-16} {1}' -f $entry.Key, $entry.Value.Description)
    }
}

$completedTask = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$activeTask = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Invoke-BuildTask {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($completedTask.Contains($Name)) {
        return
    }
    if (-not $activeTask.Add($Name)) {
        throw "Build task dependency cycle detected at '$Name'."
    }

    $definition = $script:TaskDefinition[$Name]
    foreach ($dependency in $definition.DependsOn) {
        Invoke-BuildTask -Name $dependency
    }

    Write-Host "==> $Name"
    if ($Name -eq 'help') {
        Show-BuildHelp
    }
    elseif ($null -ne $definition.Action) {
        & $definition.Action
    }

    [void]$activeTask.Remove($Name)
    [void]$completedTask.Add($Name)
}

$startingLocation = Get-Location
try {
    Set-Location -LiteralPath $script:RepositoryRoot
    Invoke-BuildTask -Name $Task
}
finally {
    Set-Location -LiteralPath $startingLocation
}
