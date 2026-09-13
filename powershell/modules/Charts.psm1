#Requires -Version 7.6
# Native bar chart, sparkline, and gauge rendering for PoshUI.

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script
$script:PoshUIStyle = Get-PoshUIStyleInternal

# ============================================================================
# Configuration
# ============================================================================

$script:PO_CHART_SPARK_CHARS = @("▁", "▂", "▃", "▄", "▅", "▆", "▇", "█")

# ============================================================================
# Utility Functions
# ============================================================================

# Find min value in array
function Get-PoshUIChartMinimumInternal {
    param([Parameter(Mandatory)][double[]]$Data)
    ($Data | Measure-Object -Minimum).Minimum
}

# Find max value in array
function Get-PoshUIChartMaximumInternal {
    param([Parameter(Mandatory)][double[]]$Data)
    ($Data | Measure-Object -Maximum).Maximum
}

# Scale value to range
# Usage: $scaled = ConvertTo-PoshUIChartScaleInternal $value $min $max $newMax
function ConvertTo-PoshUIChartScaleInternal {
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Min,
        [Parameter(Mandatory)][double]$Max,
        [Parameter(Mandatory)][double]$NewMax
    )

    if ($Max -eq $Min) {
        return [int]$NewMax
    }

    $scaled = ($Value - $Min) / ($Max - $Min) * $NewMax
    [int][math]::Round($scaled, 0)
}

# ============================================================================
# Horizontal Bar Chart
# ============================================================================

function Format-PoshUIHorizontalBarChart {
    <#
    .SYNOPSIS
    Formats a horizontal bar chart as composable text lines.

    .DESCRIPTION
    Creates a horizontal bar chart without writing to the host. In rich mode,
    the returned strings contain the configured ANSI colors. In plain and off
    modes, ANSI sequences are removed. The strings can be captured, composed,
    redirected, or passed to Show-PoshUIHorizontalBarChart.

    .PARAMETER Title
    An optional title written above the chart.

    .PARAMETER Data
    One or more numeric values to chart.

    .PARAMETER Labels
    Optional labels corresponding to the data values.

    .PARAMETER Width
    The maximum bar width in terminal cells.

    .EXAMPLE
    Format-PoshUIHorizontalBarChart -Title 'Builds' -Data 2, 4 -Labels 'Failed', 'Passed' -Width 10

    Returns the title, a blank line, and two formatted bar lines.

    .EXAMPLE
    Format-PoshUIHorizontalBarChart -Data 5, 8 -Width 20 | Set-Content chart.txt

    Saves an unlabeled chart without writing directly to the host.

    .EXAMPLE
    $lines = Format-PoshUIHorizontalBarChart -Data 1, 2, 3 -Labels A, B, C

    Captures the formatted chart lines for composition.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [double[]]$Data,

        [Parameter(Position = 2)]
        [AllowEmptyCollection()]
        [string[]]$Labels = @(),

        [Parameter(Position = 3)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width = 50
    )

    if ($Labels.Count -ne 0 -and $Labels.Count -ne $Data.Count) {
        throw 'Labels must be empty or contain one label for every data value.'
    }

    $rendered = [System.Collections.Generic.List[string]]::new()
    $max = Get-PoshUIChartMaximumInternal $Data

    if ($Title) {
        $rendered.Add("$($script:PoshUIStyle.Bold)${Title}$($script:PoshUIStyle.Reset)")
        $rendered.Add('')
    }

    $maxLabelLen = 0
    foreach ($label in $Labels) {
        if ($label.Length -gt $maxLabelLen) { $maxLabelLen = $label.Length }
    }

    for ($i = 0; $i -lt $Data.Length; $i++) {
        $value = $Data[$i]
        $line = ''
        if ($Labels.Count -gt 0) {
            $line += "{0,-$maxLabelLen} " -f $Labels[$i]
        }

        $barLen = ConvertTo-PoshUIChartScaleInternal $value 0 $max $Width
        $percent = if ($max -eq 0) { 0 } else { $value / $max * 100 }
        $barColor = if ($percent -lt 33) {
            $script:PoshUIStyle.Red
        } elseif ($percent -lt 66) {
            $script:PoshUIStyle.Yellow
        } else {
            $script:PoshUIStyle.Green
        }

        $line += $barColor + ([string]$script:PoshUIStyle.Bar * $barLen) + $script:PoshUIStyle.Reset
        $line += " $value"
        $rendered.Add($line)
    }

    foreach ($line in $rendered) {
        if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
    }
}

function Show-PoshUIHorizontalBarChart {
    <#
    .SYNOPSIS
    Displays a horizontal bar chart through the PoshUI runtime boundary.

    .DESCRIPTION
    Formats a horizontal bar chart and writes each resulting line through
    Write-PoshUIHost.

    .PARAMETER Title
    An optional title written above the chart.

    .PARAMETER Data
    One or more numeric values to chart.

    .PARAMETER Labels
    Optional labels corresponding to the data values.

    .PARAMETER Width
    The maximum bar width in terminal cells.

    .EXAMPLE
    Show-PoshUIHorizontalBarChart -Data 1, 3 -Labels 'Queued', 'Done'

    Displays a two-row horizontal bar chart.

    .EXAMPLE
    Show-PoshUIHorizontalBarChart -Title 'Jobs' -Data 2, 6

    Displays an unlabeled chart with a title.

    .EXAMPLE
    Show-PoshUIHorizontalBarChart -Data 1, 2, 3 -Width 20

    Displays a compact chart through the configured runtime.

    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [double[]]$Data,

        [Parameter(Position = 2)]
        [AllowEmptyCollection()]
        [string[]]$Labels = @(),

        [Parameter(Position = 3)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width = 50
    )

    Format-PoshUIHorizontalBarChart @PSBoundParameters |
        ForEach-Object { Write-PoshUIHost $_ }
}

# ============================================================================
# Sparklines
# ============================================================================

function Format-PoshUISparkline {
    <#
    .SYNOPSIS
    Formats numeric data as a composable sparkline string.

    .DESCRIPTION
    Scales numeric values across the configured spark glyphs and returns one
    string without writing to the host. The result is suitable for embedding in
    tables, boxes, status lines, or other formatted output.

    .PARAMETER Data
    One or more numeric values to represent.

    .PARAMETER Levels
    The number of spark glyph levels to use, from two through eight.

    .EXAMPLE
    Format-PoshUISparkline -Data 1, 2, 3, 4

    Returns a four-character sparkline.

    .EXAMPLE
    $trend = Format-PoshUISparkline -Data 8, 5, 7 -Levels 4

    Captures a sparkline using four glyph levels.

    .EXAMPLE
    "Latency: $(Format-PoshUISparkline -Data 10, 12, 9)"

    Composes the returned sparkline into another string.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [double[]]$Data,

        [Parameter(Position = 1)]
        [ValidateRange(2, 8)]
        [int]$Levels = 8
    )

    $min = Get-PoshUIChartMinimumInternal $Data
    $max = Get-PoshUIChartMaximumInternal $Data
    $characters = foreach ($value in $Data) {
        $scaled = ConvertTo-PoshUIChartScaleInternal $value $min $max ($Levels - 1)
        $script:PO_CHART_SPARK_CHARS[$scaled]
    }
    $characters -join ''
}

function Show-PoshUISparkline {
    <#
    .SYNOPSIS
    Displays a sparkline through the PoshUI runtime boundary.

    .DESCRIPTION
    Formats numeric data as a sparkline and writes it through Write-PoshUIHost.
    By default, no trailing newline is written so the sparkline remains inline.

    .PARAMETER Data
    One or more numeric values to represent.

    .PARAMETER Levels
    The number of spark glyph levels to use, from two through eight.

    .PARAMETER Newline
    Writes a trailing newline after the sparkline.

    .EXAMPLE
    Show-PoshUISparkline -Data 4, 3, 6, 8

    Displays an inline four-character sparkline.

    .EXAMPLE
    Show-PoshUISparkline -Data 4, 3, 6, 8 -Newline

    Displays a sparkline followed by a newline.

    .EXAMPLE
    Show-PoshUISparkline -Data 1, 5, 3 -Levels 4

    Displays a sparkline using four glyph levels.

    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [double[]]$Data,

        [Parameter(Position = 1)]
        [ValidateRange(2, 8)]
        [int]$Levels = 8,

        [Parameter()]
        [switch]$Newline
    )

    $sparkline = Format-PoshUISparkline -Data $Data -Levels $Levels
    Write-PoshUIHost $sparkline -NoNewline:(-not $Newline)
}

# Generate sparkline (mini inline chart)
# ============================================================================
# Gauge / Progress Indicator
# ============================================================================

function Format-PoshUIGauge {
    <#
    .SYNOPSIS
    Formats a gauge as a composable text line.

    .DESCRIPTION
    Creates a labeled or unlabeled gauge without writing to the host. Rich mode
    includes the configured ANSI color, while plain and off modes return the
    same visual content without ANSI sequences.

    .PARAMETER Value
    The current gauge value. It must be between zero and Max.

    .PARAMETER Max
    The positive value representing a full gauge.

    .PARAMETER Label
    Optional text placed before the gauge.

    .PARAMETER Width
    The number of terminal cells used by the filled and empty bar.

    .EXAMPLE
    Format-PoshUIGauge -Value 3 -Max 4 -Label 'Ready' -Width 8

    Returns one formatted gauge line.

    .EXAMPLE
    $line = Format-PoshUIGauge -Value 40 -Max 100

    Captures an unlabeled gauge for composition.

    .EXAMPLE
    Format-PoshUIGauge -Value 5 -Max 10 | Set-Content gauge.txt

    Saves a gauge without writing directly to the host.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$Value,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange([double]::Epsilon, [double]::MaxValue)]
        [double]$Max,

        [Parameter(Position = 2)]
        [AllowEmptyString()]
        [string]$Label = '',

        [Parameter(Position = 3)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width = 30
    )

    if ($Value -gt $Max) {
        throw 'Value cannot be greater than Max.'
    }

    $percent = $Value / $Max * 100
    $filled = ConvertTo-PoshUIChartScaleInternal $Value 0 $Max $Width
    $color = if ($percent -lt 33) {
        $script:PoshUIStyle.Red
    } elseif ($percent -lt 66) {
        $script:PoshUIStyle.Yellow
    } else {
        $script:PoshUIStyle.Green
    }

    $line = if ($Label) { "${Label}: " } else { '' }
    $line += '['
    $line += $color + ([string]$script:PoshUIStyle.Bar * $filled) + $script:PoshUIStyle.Reset
    $line += [string]$script:PoshUIStyle.EmptyBar * ($Width - $filled)
    $line += '] '
    $line += "${color}{0:F1}%$($script:PoshUIStyle.Reset) ($Value/$Max)" -f $percent

    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
}

function Show-PoshUIGauge {
    <#
    .SYNOPSIS
    Displays a gauge through the PoshUI runtime boundary.

    .DESCRIPTION
    Formats a gauge with Format-PoshUIGauge and writes it through
    Write-PoshUIHost.

    .PARAMETER Value
    The current gauge value. It must be between zero and Max.

    .PARAMETER Max
    The positive value representing a full gauge.

    .PARAMETER Label
    Optional text placed before the gauge.

    .PARAMETER Width
    The number of terminal cells used by the filled and empty bar.

    .EXAMPLE
    Show-PoshUIGauge -Value 75 -Max 100 -Label 'Deploy'

    Displays one gauge line.

    .EXAMPLE
    Show-PoshUIGauge -Value 3 -Max 5 -Width 12

    Displays a compact unlabeled gauge.

    .EXAMPLE
    Show-PoshUIGauge -Value 1 -Max 4 -Label 'Queued' -Width 8

    Displays a labeled gauge with a custom width.

    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$Value,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange([double]::Epsilon, [double]::MaxValue)]
        [double]$Max,

        [Parameter(Position = 2)]
        [AllowEmptyString()]
        [string]$Label = '',

        [Parameter(Position = 3)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width = 30
    )

    Write-PoshUIHost (Format-PoshUIGauge @PSBoundParameters)
}

# Draw circular gauge
Export-ModuleMember -Function @(
    'Format-PoshUIHorizontalBarChart'
    'Show-PoshUIHorizontalBarChart'
    'Format-PoshUISparkline'
    'Show-PoshUISparkline'
    'Format-PoshUIGauge'
    'Show-PoshUIGauge'
)
