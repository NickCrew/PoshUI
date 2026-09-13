#Requires -Version 7.6
# Invoke-Benchmark.ps1 - Performance benchmark suite for PoshUI (PowerShell)
#
# 13 named benchmarks, iteration
# counts, and three-section grouping, timed against the PowerShell modules.
# Measures with System.Diagnostics.Stopwatch. Writes no file unless
# -OutputPath is given.

[CmdletBinding()]
param(
    # Scale factor applied to every baseline iteration count. 1 keeps the
    # counts from benchmark.sh; 0.01 is a quick smoke run.
    [double]$Iterations = 1,

    # Optional CSV destination. Omitted means nothing is written to disk.
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Iterations -lt 0) {
    throw [System.ArgumentOutOfRangeException]::new(
        'Iterations',
        $Iterations,
        'Scale factor must be greater than or equal to 0.'
    )
}

$manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' 'PoshUI.psd1'))
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "PoshUI manifest not found at $manifestPath"
}

Import-Module -Name $manifestPath -Force

$script:BenchmarkResults = [System.Collections.Generic.List[object]]::new()
$script:BenchmarkTotalMs = 0.0

function Get-ScaledCount {
    param([int]$BaseCount)

    if ($Iterations -le 0) {
        return 0
    }

    # Ceiling so a fractional scale cannot drop a benchmark to zero
    # iterations (0.01 * 50 = 0.5; bankers' Round would become 0).
    [int][Math]::Max(1, [Math]::Ceiling($BaseCount * $Iterations))
}

# Time one benchmark. Console.Out/Error are redirected for the whole loop
# so explicit-rich output is silent; *>$null swallows host and stream output.
# Redirection is set up once around the loop, not per iteration.
function Invoke-TimedBenchmark {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$BaseCount,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $count = Get-ScaledCount $BaseCount
    $oldOut = [Console]::Out
    $oldError = [Console]::Error
    $sw = [System.Diagnostics.Stopwatch]::new()

    try {
        [Console]::SetOut([System.IO.TextWriter]::Null)
        [Console]::SetError([System.IO.TextWriter]::Null)

        $sw.Start()
        & {
            for ($n = 0; $n -lt $count; $n++) {
                & $Action
            }
        } *>$null
        $sw.Stop()
    }
    finally {
        [Console]::SetOut($oldOut)
        [Console]::SetError($oldError)
        if ($sw.IsRunning) {
            $sw.Stop()
        }
    }

    $elapsedMs = $sw.Elapsed.TotalMilliseconds
    $perOpUs = if ($count -gt 0) { ($elapsedMs * 1000.0) / $count } else { 0.0 }

    $script:BenchmarkTotalMs += $elapsedMs
    $script:BenchmarkResults.Add([pscustomobject]@{
            Benchmark                = $Name
            Iterations               = $count
            TotalMilliseconds        = [Math]::Round($elapsedMs, 4)
            MicrosecondsPerOperation = [Math]::Round($perOpUs, 4)
        })

    Show-PoshUISubheader -Title ('{0} ({1} iterations): {2:N2}ms total ({3:N2}µs per iteration)' -f $Name, $count, $elapsedMs, $perOpUs)
}

Show-PoshUIHeader -Label 'BENCH' -Title 'PoshUI PowerShell Benchmark Suite'

# ============================================================================
# Core operations
# ============================================================================

Show-PoshUIHeader -Label 'CORE' -Title 'Core operations'

Invoke-TimedBenchmark 'Text Layout' 10000 {
    [void](Format-PoshUIText -InputObject 'Test text layout' -Width 24 -HorizontalAlignment Center)
}

Invoke-TimedBenchmark 'Unicode Layout' 10000 {
    [void](Format-PoshUIText -InputObject 'Test 🚀 emoji 📊 width 🔥' -Width 24 -Overflow Truncate)
}

Invoke-TimedBenchmark 'Logging' 5000 {
    Write-PoshUILog -Level Info -Message 'Test message'
}

Invoke-TimedBenchmark 'Progress Bar' 1000 {
    $progress = New-PoshUIProgress -Current 50 -Total 100 -Label 'Testing'
    [void](Format-PoshUIProgress -Progress $progress)
}

# ============================================================================
# Rendering
# ============================================================================

Show-PoshUIHeader -Label 'RENDER' -Title 'Rendering'

Invoke-TimedBenchmark 'Box Drawing' 500 {
    [void](Format-PoshUIBox -Title 'Test' -Content @('This is a test message', 'With multiple lines', 'And emoji 🚀'))
}

Invoke-TimedBenchmark 'Table Rendering' 200 {
    $table = New-PoshUITable -Style Rounded -Header @('Name', 'Value', 'Status')
    Add-PoshUITableRow -Table $table -Values @('Test1', '100', '✓ OK')
    Add-PoshUITableRow -Table $table -Values @('Test2', '200', '✓ OK')
    Add-PoshUITableRow -Table $table -Values @('Test3', '300', '✓ OK')
    [void](Format-PoshUITable -Table $table)
}

Invoke-TimedBenchmark 'Sparkline' 500 {
    [void](Format-PoshUISparkline -Data @(10, 20, 30, 25, 35, 40, 30, 45, 50, 55))
}

Invoke-TimedBenchmark 'Gauge' 500 {
    [void](Format-PoshUIGauge -Value 75 -Max 100 -Label 'CPU' -Width 30)
}

# Creation only: Show-PoshUIMenu reads from a TTY.
Invoke-TimedBenchmark 'Menu Creation' 500 {
    $menu = New-PoshUIMenu -Title 'Test Menu'
    Add-PoshUIMenuItem -Menu $menu -Label 'Option 1' -Action { $true } -Hotkey '1'
    Add-PoshUIMenuItem -Menu $menu -Label 'Option 2' -Action { $true } -Hotkey '2'
    Add-PoshUIMenuItem -Menu $menu -Label 'Option 3' -Action { $true } -Hotkey '3'
    [void](Format-PoshUIMenu -Menu $menu)
}

Invoke-TimedBenchmark 'Chart Generation' 200 {
    [void](Format-PoshUIHorizontalBarChart -Title 'Test' -Data @(10, 20, 30, 40, 50) -Labels @('A', 'B', 'C', 'D', 'E') -Width 20)
}

# ============================================================================
# Stress tests
# ============================================================================

Show-PoshUIHeader -Label 'STRESS' -Title 'Stress tests'

Invoke-TimedBenchmark 'Large Table (50 rows)' 50 {
    $table = New-PoshUITable -Style Rounded -Header @('Col1', 'Col2', 'Col3', 'Col4', 'Col5')
    for ($row = 1; $row -le 50; $row++) {
        Add-PoshUITableRow -Table $table -Values @("Row$row", "Value$row", "Status$row", "Data$row", "Info$row")
    }
    [void](Format-PoshUITable -Table $table)
}

Invoke-TimedBenchmark 'Many Boxes (20)' 50 {
    for ($boxNum = 1; $boxNum -le 20; $boxNum++) {
        [void](Format-PoshUIBox -Title "Message $boxNum" -Content "Content for message $boxNum")
    }
}

Invoke-TimedBenchmark 'Long Sparkline (100 points)' 100 {
    $data = [double[]]::new(100)
    for ($p = 0; $p -lt 100; $p++) {
        $data[$p] = Get-Random -Maximum 100
    }
    [void](Format-PoshUISparkline -Data $data)
}

Show-PoshUIBox -Title 'Benchmark complete' -Content ('Total benchmark time: {0:N2}ms' -f $script:BenchmarkTotalMs)

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $script:BenchmarkResults |
        Select-Object Benchmark, Iterations, TotalMilliseconds, MicrosecondsPerOperation |
        Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
}
