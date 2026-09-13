#Requires -Version 7.6

<#
.SYNOPSIS
    Dispatches PoshUI CLI verbs to the PowerShell port

.DESCRIPTION
    Single entry point for the PowerShell port of PoshUI. Resolves the
    framework root from this script's location (or POSH_UI_HOME), then
    maps a verb to the matching tool or example script.

    Remaining arguments after the verb are forwarded to the target script
    unchanged, so `posh-ui.ps1 demo -Auto` reaches Showcase.ps1 as -Auto.

    When a target script is missing, the CLI prints the resolved path and
    exits 1 instead of throwing a raw PowerShell error.

.PARAMETER Command
    Verb to run. One of validate, benchmark, demo, dashboard, examples,
    help, version, info. Omitted, the CLI prints usage and exits 0.

.PARAMETER CommandArgs
    Arguments forwarded to the target script. Bound from leftover tokens
    after -Command, including switches such as -Auto and -NoPause.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.String

    Usage, version, and info text. Delegated verbs emit whatever the
    target script writes.

.EXAMPLE
    PS> ./posh-ui.ps1

    Prints usage and exits 0.

.EXAMPLE
    PS> ./posh-ui.ps1 version

    Prints the framework version from the module manifest.

.EXAMPLE
    PS> ./posh-ui.ps1 demo -Auto

    Runs powershell/examples/Showcase.ps1 with -Auto.

.EXAMPLE
    PS> ./posh-ui.ps1 examples -NoPause

    Runs powershell/examples/Examples.ps1 without interactive pauses.

.NOTES
    Requires PowerShell 7.6 or later.

    Exit codes: 0 success (including default help), 1 unknown verb,
    missing target, or the target script's own non-zero exit code.

    POSH_UI_HOME overrides the resolved root, which otherwise is the
    parent of this script's directory (the powershell/ folder).

.LINK
    about_Scripts
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Paths
# ============================================================================

# Match bin/posh-ui line 11: POSH_UI_HOME, else parent of the script dir.
if (-not [string]::IsNullOrWhiteSpace($env:POSH_UI_HOME)) {
    $script:PoshUIHome = [System.IO.Path]::GetFullPath($env:POSH_UI_HOME)
}
else {
    $script:PoshUIHome = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

$script:ModulesDir = Join-Path $script:PoshUIHome 'modules'
$script:ExamplesDir = Join-Path $script:PoshUIHome 'examples'
$script:TestsDir = Join-Path $script:PoshUIHome 'tests'
$script:ToolsDir = Join-Path $script:PoshUIHome 'tools'
$script:RepoRoot = Split-Path -Parent $script:PoshUIHome
$script:Version = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $script:PoshUIHome 'PoshUI.psd1')).ModuleVersion

# Copy remaining tokens now so nested functions do not re-bind them.
$script:ForwardedArgs = [string[]]@()
if ($null -ne $CommandArgs -and $CommandArgs.Count -gt 0) {
    $script:ForwardedArgs = [string[]]@($CommandArgs)
}

# ============================================================================
# Helpers
# ============================================================================

function Get-DocText {
    # Both a checkout and an installed module land here, and the two lay their
    # docs out differently. Listing a path that is not there is worse than
    # listing nothing, so each label takes the first candidate that exists and
    # is dropped otherwise.
    $candidates = [ordered]@{
        'README'       = @(
            (Join-Path $script:RepoRoot 'README.md')
            (Join-Path $script:PoshUIHome 'README.md')
        )
        'Module'       = @((Join-Path $script:PoshUIHome 'README.md'))
        'Testing'      = @((Join-Path $script:RepoRoot 'docs' 'testing' 'TESTING.md'))
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($label in $candidates.Keys) {
        $found = $candidates[$label] |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($null -ne $found) {
            [void]$lines.Add(('  {0,-13} {1}' -f ($label + ':'), $found))
        }
    }

    if ($lines.Count -eq 0) {
        return '  (none found in this install)'
    }
    $lines -join [Environment]::NewLine
}

function Get-UsageText {
    @"
╔════════════════════════════════════════════════════════════════════════════╗
║                            PoshUI CLI v$($script:Version)                               ║
║               Beautiful Terminal UI Framework for PowerShell               ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE:
  posh-ui.ps1 <command> [options]
  posh-ui.ps1 -Command <command> [options]

COMMANDS:
  validate              Run the validation test suite
  benchmark             Run performance benchmarks
  demo                  Run the interactive showcase
  dashboard             Run the ultimate dashboard example
  examples              Run all examples
  help                  Show this help message
  version               Show version information
  info                  Show installation information

EXAMPLES:
  posh-ui.ps1 validate
  posh-ui.ps1 benchmark
  posh-ui.ps1 demo -Auto
  posh-ui.ps1 dashboard -Auto -Iterations 1 -RefreshInterval 1
  posh-ui.ps1 examples -NoPause

DOCUMENTATION:
$(Get-DocText)

QUICK START:
  Import-Module $(Join-Path $script:PoshUIHome 'PoshUI.psd1')

  Show-PoshUIBox -Title 'Hello!' -Content 'PoshUI makes terminals readable'
  New-PoshUIProgress -Total 100 -Current 75 -Label Processing | Show-PoshUIProgress
"@
}

function Show-Usage {
    param([switch]$AsError)

    $text = Get-UsageText
    if ($AsError) {
        [Console]::Error.WriteLine($text)
        return
    }
    Write-Output $text
}

function Invoke-TargetScript {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        [Console]::Error.WriteLine("Target script not found: $LiteralPath")
        exit 1
    }

    # Launch a child pwsh so leftover tokens such as -NoPause and -Auto
    # bind as named parameters on the target. Splatting a string array at
    # a PowerShell command passes those tokens positionally, which switch
    # parameters reject.
    $invocation = [System.Collections.Generic.List[string]]::new()
    [void]$invocation.Add('-NoProfile')
    [void]$invocation.Add('-File')
    [void]$invocation.Add($LiteralPath)
    foreach ($token in $script:ForwardedArgs) {
        [void]$invocation.Add($token)
    }

    $global:LASTEXITCODE = 0
    & pwsh @($invocation.ToArray())
    if ($null -eq $LASTEXITCODE) {
        exit 0
    }
    exit $LASTEXITCODE
}

# ============================================================================
# Commands
# ============================================================================

function Invoke-ValidateCommand {
    Invoke-TargetScript -LiteralPath (Join-Path $script:TestsDir 'Invoke-Tests.ps1')
}

function Invoke-BenchmarkCommand {
    Invoke-TargetScript -LiteralPath (Join-Path $script:ToolsDir 'Invoke-Benchmark.ps1')
}

function Invoke-DemoCommand {
    Invoke-TargetScript -LiteralPath (Join-Path $script:ExamplesDir 'Showcase.ps1')
}

function Invoke-DashboardCommand {
    Invoke-TargetScript -LiteralPath (Join-Path $script:ExamplesDir 'Ultimate-Dashboard.ps1')
}

function Invoke-ExamplesCommand {
    Invoke-TargetScript -LiteralPath (Join-Path $script:ExamplesDir 'Examples.ps1')
}

function Show-Version {
    Write-Output "PoshUI v$($script:Version)"
    Write-Output 'PowerShell Terminal UI Framework'
    Write-Output ''
    Write-Output "Installation: $($script:PoshUIHome)"
    Write-Output "PowerShell:   $($PSVersionTable.PSVersion)"
}

function Show-Info {
    $moduleCount = 0
    if (Test-Path -LiteralPath $script:ModulesDir -PathType Container) {
        $moduleCount = @(
            Get-ChildItem -LiteralPath $script:ModulesDir -Filter '*.psm1' -File
        ).Count
    }

    Write-Output @"
╔════════════════════════════════════════════════════════════════════════════╗
║                    PoshUI Installation Info                                ║
╚════════════════════════════════════════════════════════════════════════════╝

Version:            $($script:Version)
Module directory:   $($script:ModulesDir)
Modules:            $moduleCount
PowerShell:         $($PSVersionTable.PSVersion)
Installation:       $($script:PoshUIHome)

DOCS:
$(Get-DocText)
"@
}

# ============================================================================
# Main
# ============================================================================

if ([string]::IsNullOrWhiteSpace($Command)) {
    $Command = 'help'
}

switch -Regex ($Command) {
    '^(?i:validate|test)$' {
        Invoke-ValidateCommand
    }
    '^(?i:benchmark|bench|perf)$' {
        Invoke-BenchmarkCommand
    }
    '^(?i:demo|showcase)$' {
        Invoke-DemoCommand
    }
    '^(?i:dashboard|dash)$' {
        Invoke-DashboardCommand
    }
    '^(?i:examples|ex)$' {
        Invoke-ExamplesCommand
    }
    '^(?i:help|--help|-h)$' {
        Show-Usage
        exit 0
    }
    '^(?i:version|--version|-v)$' {
        Show-Version
        exit 0
    }
    '^(?i:info|about)$' {
        Show-Info
        exit 0
    }
    default {
        Show-Usage -AsError
        exit 1
    }
}
