#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop

function Get-PoshUIDataElementWidth {
    param([Parameter(Mandatory)][string]$TextElement)
    $width = 0
    $emoji = $false
    foreach ($rune in $TextElement.EnumerateRunes()) {
        $codepoint = $rune.Value
        if ($codepoint -eq 0x200D -or $codepoint -eq 0xFE0F) { $emoji = $true; continue }
        if ($codepoint -eq 0xFE0E) { continue }
        if ([System.Text.Rune]::GetUnicodeCategory($rune) -in @(
            [System.Globalization.UnicodeCategory]::NonSpacingMark,
            [System.Globalization.UnicodeCategory]::EnclosingMark,
            [System.Globalization.UnicodeCategory]::Format
        )) { continue }
        if (($codepoint -ge 0x1F1E6 -and $codepoint -le 0x1FAFF)) { $emoji = $true }
        $wide = ($codepoint -ge 0x1100 -and $codepoint -le 0x115F) -or
            ($codepoint -ge 0x2E80 -and $codepoint -le 0xA4CF) -or
            ($codepoint -ge 0xAC00 -and $codepoint -le 0xD7A3) -or
            ($codepoint -ge 0xF900 -and $codepoint -le 0xFAFF) -or
            ($codepoint -ge 0xFE10 -and $codepoint -le 0xFE6F) -or
            ($codepoint -ge 0xFF00 -and $codepoint -le 0xFF60) -or
            ($codepoint -ge 0xFFE0 -and $codepoint -le 0xFFE6) -or
            ($codepoint -ge 0x20000 -and $codepoint -le 0x3FFFD)
        $width += $(if ($wide) { 2 } else { 1 })
    }
    if ($emoji) { return 2 }
    $width
}

function Measure-PoshUIDataText {
    param([AllowEmptyString()][string]$Text)
    $plain = ConvertTo-PoshUIPlainText $Text
    $width = 0
    $elements = [System.Globalization.StringInfo]::GetTextElementEnumerator($plain)
    while ($elements.MoveNext()) { $width += Get-PoshUIDataElementWidth ([string]$elements.Current) }
    $width
}

function New-PoshUIDataColumn {
    <#
    .SYNOPSIS
    Creates a typed object-table column definition
    .DESCRIPTION
    Creates an independent column definition for Format-PoshUIDataTable. A
    column selects one object property and can apply its own formatter, maximum
    width, overflow behavior, and alignment. It does not read or change global
    table state.
    .PARAMETER Property
    Property name read from each pipeline object.
    .PARAMETER Name
    Header label. Defaults to Property.
    .PARAMETER Formatter
    Script block invoked with the property value and source object.
    .PARAMETER MaxWidth
    Maximum rendered width. Zero uses the table-level maximum.
    .PARAMETER Overflow
    Wrap preserves all text on continuation rows. Truncate uses an ellipsis.
    .PARAMETER Alignment
    Cell alignment within the resolved column width.
    .INPUTS
    None
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    New-PoshUIDataColumn -Property Name

    Creates a column whose label and property are Name.
    .EXAMPLE
    New-PoshUIDataColumn -Property Duration -Name Seconds -Formatter { param($value) '{0:N2}' -f $value }

    Creates a calculated presentation for Duration.
    .EXAMPLE
    New-PoshUIDataColumn -Property Notes -MaxWidth 20 -Overflow Wrap

    Creates a wrapping Notes column.
    .NOTES
    Column definitions are immutable by convention and safe to reuse.
    .LINK
    Format-PoshUIDataTable
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory value without changing external state.')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Property,
        [ValidateNotNullOrEmpty()][string]$Name = $Property,
        [scriptblock]$Formatter,
        [ValidateRange(0, [int]::MaxValue)][int]$MaxWidth = 0,
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Truncate',
        [ValidateSet('Left', 'Right', 'Center')][string]$Alignment = 'Left'
    )

    [pscustomobject]@{
        PSTypeName = 'PoshUI.DataColumn'
        Property   = $Property
        Name       = $Name
        Formatter  = $Formatter
        MaxWidth   = $MaxWidth
        Overflow   = $Overflow
        Alignment  = $Alignment
    }
}

function Format-PoshUIDataTable {
    <#
    .SYNOPSIS
    Formats pipeline objects as a structured data table
    .DESCRIPTION
    Buffers pipeline objects, selects properties without delimiter encoding,
    optionally sorts and pages them, and returns plain composable text lines.
    Embedded delimiters remain cell data and embedded newlines become visual
    continuation rows. This command never writes to the host.
    .PARAMETER InputObject
    Objects to render. Accepts pipeline input.
    .PARAMETER Property
    Property names or PoshUI.DataColumn definitions. Omitted, properties are
    inferred from the first object.
    .PARAMETER SortBy
    Property used to sort before paging.
    .PARAMETER Descending
    Sorts descending instead of ascending.
    .PARAMETER Page
    One-based page number.
    .PARAMETER PageSize
    Rows per page. Zero disables paging.
    .PARAMETER MaxColumnWidth
    Default maximum width for columns without their own maximum.
    .PARAMETER Overflow
    Default overflow behavior for property-name columns.
    .INPUTS
    System.Object
    .OUTPUTS
    System.String
    .EXAMPLE
    Get-Process | Select-Object -First 5 | Format-PoshUIDataTable -Property Name, Id

    Formats process names and identifiers.
    .EXAMPLE
    $notes = New-PoshUIDataColumn -Property Notes -MaxWidth 12 -Overflow Wrap
    $items | Format-PoshUIDataTable -Property Name, $notes

    Wraps the Notes column while preserving embedded newlines.
    .EXAMPLE
    $items | Format-PoshUIDataTable -Property Name, Score -SortBy Score -Descending -Page 2 -PageSize 10

    Returns the second page after descending score sort.
    .NOTES
    Rendering uses an ASCII border so redirected output is stable.
    .LINK
    New-PoshUIDataColumn
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][object]$InputObject,
        [ValidateNotNullOrEmpty()][object[]]$Property,
        [ValidateNotNullOrEmpty()][string]$SortBy,
        [switch]$Descending,
        [ValidateRange(1, [int]::MaxValue)][int]$Page = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$PageSize = 0,
        [ValidateRange(1, [int]::MaxValue)][int]$MaxColumnWidth = 40,
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Truncate'
    )

    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        if ($items.Count -eq 0) { return }

        $columns = [System.Collections.Generic.List[object]]::new()
        if ($Property) {
            foreach ($entry in $Property) {
                if ($entry.PSObject.TypeNames -contains 'PoshUI.DataColumn') {
                    $columns.Add($entry)
                }
                elseif ($entry -is [string]) {
                    $columns.Add((New-PoshUIDataColumn -Property $entry -MaxWidth $MaxColumnWidth -Overflow $Overflow))
                }
                else {
                    throw 'Property entries must be property names or PoshUI.DataColumn definitions.'
                }
            }
        }
        else {
            foreach ($propertyInfo in $items[0].PSObject.Properties) {
                $columns.Add((New-PoshUIDataColumn -Property $propertyInfo.Name -MaxWidth $MaxColumnWidth -Overflow $Overflow))
            }
        }
        if ($columns.Count -eq 0) { throw 'No renderable properties were found.' }

        [object[]]$ordered = $items.ToArray()
        if ($SortBy) {
            $ordered = @($ordered | Sort-Object -Property $SortBy -Descending:$Descending)
        }

        $totalRows = $ordered.Count
        $totalPages = 1
        if ($PageSize -gt 0) {
            $totalPages = [Math]::Max(1, [Math]::Ceiling($totalRows / [double]$PageSize))
            if ($Page -gt $totalPages) { throw "Page $Page exceeds the available page count of $totalPages." }
            $start = ($Page - 1) * $PageSize
            $take = [Math]::Min($PageSize, $totalRows - $start)
            $ordered = if ($take -gt 0) { @($ordered[$start..($start + $take - 1)]) } else { @() }
        }

        $rawRows = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $ordered) {
            $cells = [System.Collections.Generic.List[string]]::new()
            foreach ($column in $columns) {
                $value = $item.PSObject.Properties[$column.Property].Value
                if ($column.Formatter) {
                    $value = @(& $column.Formatter $value $item) -join [Environment]::NewLine
                }
                $cells.Add($(if ($null -eq $value) { '' } else { [string]$value }))
            }
            $rawRows.Add($cells.ToArray())
        }

        $widths = [System.Collections.Generic.List[int]]::new()
        for ($index = 0; $index -lt $columns.Count; $index++) {
            $column = $columns[$index]
            $limit = if ($column.MaxWidth -gt 0) { $column.MaxWidth } else { $MaxColumnWidth }
            $width = [Math]::Min($limit, [Math]::Max(1, (Measure-PoshUIDataText ([string]$column.Name))))
            foreach ($row in $rawRows) {
                foreach ($line in [regex]::Split($row[$index], "\r\n|\n|\r")) {
                    $width = [Math]::Max($width, [Math]::Min($limit, [Math]::Max(1, (Measure-PoshUIDataText $line))))
                }
            }
            $widths.Add($width)
        }

        $border = '+' + (($widths | ForEach-Object { '-' * ($_ + 2) }) -join '+') + '+'
        $border
        $headerCells = for ($index = 0; $index -lt $columns.Count; $index++) {
            Format-PoshUIText -InputObject ([string]$columns[$index].Name) -Width $widths[$index] -Overflow Truncate
        }
        '| ' + ($headerCells -join ' | ') + ' |'
        $border

        foreach ($row in $rawRows) {
            $cellLines = [System.Collections.Generic.List[object]]::new()
            $height = 1
            for ($index = 0; $index -lt $columns.Count; $index++) {
                $lines = @(Format-PoshUIText -InputObject $row[$index] -Width $widths[$index] -Overflow $columns[$index].Overflow -HorizontalAlignment $columns[$index].Alignment)
                $cellLines.Add($lines)
                $height = [Math]::Max($height, $lines.Count)
            }
            for ($visualRow = 0; $visualRow -lt $height; $visualRow++) {
                $renderedCells = for ($index = 0; $index -lt $columns.Count; $index++) {
                    if ($visualRow -lt $cellLines[$index].Count) {
                        [string]$cellLines[$index][$visualRow]
                    }
                    else { ' ' * $widths[$index] }
                }
                '| ' + ($renderedCells -join ' | ') + ' |'
            }
        }
        $border
        if ($PageSize -gt 0) { "[Page $Page of $totalPages, $totalRows rows]" }
    }
}

function Show-PoshUIDataTable {
    <#
    .SYNOPSIS
    Displays pipeline objects as a structured data table
    .DESCRIPTION
    Applies the Format-PoshUIDataTable contract and writes each resulting line
    through the shared PoshUI host boundary. Off mode suppresses host effects.
    .PARAMETER InputObject
    Objects to display. Accepts pipeline input.
    .PARAMETER Property
    Property names or PoshUI.DataColumn definitions.
    .PARAMETER SortBy
    Property used to sort before paging.
    .PARAMETER Descending
    Sorts descending.
    .PARAMETER Page
    One-based page number.
    .PARAMETER PageSize
    Rows per page. Zero disables paging.
    .PARAMETER MaxColumnWidth
    Default maximum column width.
    .PARAMETER Overflow
    Default overflow behavior.
    .INPUTS
    System.Object
    .OUTPUTS
    None
    .EXAMPLE
    $items | Show-PoshUIDataTable -Property Name, State

    Displays two selected properties.
    .EXAMPLE
    $items | Show-PoshUIDataTable -Property Name, Notes -Overflow Wrap -MaxColumnWidth 20

    Displays wrapped values.
    .EXAMPLE
    $items | Show-PoshUIDataTable -Property Name -Page 1 -PageSize 25

    Displays the first page.
    .NOTES
    This is the effectful wrapper for Format-PoshUIDataTable.
    .LINK
    Format-PoshUIDataTable
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][object]$InputObject,
        [ValidateNotNullOrEmpty()][object[]]$Property,
        [ValidateNotNullOrEmpty()][string]$SortBy,
        [switch]$Descending,
        [ValidateRange(1, [int]::MaxValue)][int]$Page = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$PageSize = 0,
        [ValidateRange(1, [int]::MaxValue)][int]$MaxColumnWidth = 40,
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Truncate'
    )
    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        $parameters = @{
            Descending = $Descending; Page = $Page; PageSize = $PageSize
            MaxColumnWidth = $MaxColumnWidth; Overflow = $Overflow
        }
        if ($Property) { $parameters.Property = $Property }
        if ($SortBy) { $parameters.SortBy = $SortBy }
        foreach ($line in @($items.ToArray() | Format-PoshUIDataTable @parameters)) { Write-PoshUIHost $line }
    }
}

Export-ModuleMember -Function @('New-PoshUIDataColumn', 'Format-PoshUIDataTable', 'Show-PoshUIDataTable')
