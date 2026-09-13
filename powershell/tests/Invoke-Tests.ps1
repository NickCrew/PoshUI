#Requires -Version 7.6

<#
.SYNOPSIS
    Runs the PoshUI Pester suite and exits non-zero on failure

.DESCRIPTION
    Clears inherited POSH_UI_* environment variables and invokes every module
    test in powershell/tests. In a repository checkout, it also invokes the
    maintainer tests in the root tests directory. It prints a pass/fail summary
    and exits 0 when every test passed or 1 when any test failed.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Writes a summary to the host and sets the process exit code.

.EXAMPLE
    PS> pwsh -NoProfile -File ./powershell/tests/Invoke-Tests.ps1

    Runs the suite from the repository root.

.EXAMPLE
    PS> pwsh -NoProfile -File ./powershell/tests/Invoke-Tests.ps1; echo $LASTEXITCODE

    Same run, then prints the exit code.

.EXAMPLE
    PS> if (pwsh -NoProfile -File ./powershell/tests/Invoke-Tests.ps1) { 'ok' }

    Uses the exit code as a gate.

.NOTES
    Requires PowerShell 7.6 and Pester 6.0.1.

    Exit codes: 0 all tests passed, 1 one or more tests failed.

.LINK
    https://pester.dev/docs/quick-start
#>

[CmdletBinding()]
[OutputType([void])]
param(
    # Where to write a JUnit report. Resolved before the Set-Location below, so
    # a relative path means relative to the caller, not to the module root.
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($OutputPath) {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath, (Get-Location).Path)
}

# The module root, not the repository: an installed module has no powershell/
# subdirectory, and the CLI `validate` verb runs this from there too.
$moduleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $moduleRoot

Get-ChildItem Env: | Where-Object { $_.Name -like 'POSH_UI_*' } | ForEach-Object {
    Remove-Item -LiteralPath ('Env:{0}' -f $_.Name)
}

Import-Module Pester -RequiredVersion 6.0.1 -ErrorAction Stop

$testPath = @($PSScriptRoot)
$repositoryRoot = Split-Path -Parent $moduleRoot
$repositoryTests = Join-Path $repositoryRoot 'tests'
$publishScript = Join-Path $repositoryRoot 'tools' 'Publish-PoshUIModule.ps1'
if ((Test-Path -LiteralPath $repositoryTests -PathType Container) -and
    (Test-Path -LiteralPath $publishScript -PathType Leaf)) {
    $testPath += $repositoryTests
}

$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Output.Verbosity = 'Detailed'

if ($OutputPath) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'JUnitXml'
    $config.TestResult.OutputPath = $OutputPath
}

$result = Invoke-Pester -Configuration $config

$pesterModule = Get-Module Pester
Write-Host ''
Write-Host '=========================================='
Write-Host '           PESTER RESULTS'
Write-Host '=========================================='
Write-Host ''
Write-Host ("Pester:       {0}" -f $pesterModule.Version)
Write-Host ("Tests run:    {0}" -f $result.TotalCount)
Write-Host ("Tests passed: {0}" -f $result.PassedCount)
Write-Host ("Tests failed: {0}" -f $result.FailedCount)
Write-Host ("Tests skipped: {0}" -f $result.SkippedCount)
Write-Host ''

if ($result.FailedCount -gt 0) {
    Write-Host 'Failed tests:'
    foreach ($test in $result.Failed) {
        Write-Host ("  - {0}" -f $test.ExpandedPath)
    }
    Write-Host ''
    exit 1
}

if ($result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0) {
    exit 1
}

Write-Host 'ALL TESTS PASSED'
exit 0
