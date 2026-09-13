#Requires -Version 7.6
# Native independent table models and rendering for PoshUI.

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Configuration.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Colors.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script
$script:PoshUIStyle = Get-PoshUIStyleInternal
$script:PoshUITableConfiguration = (Get-PoshUIConfiguration).Table

# ============================================================================
# Box Drawing Characters by Style
# ============================================================================

# A hashtable lookup rather than dynamic variable-name evaluation
# with a real nested hashtable, PowerShell has associative arrays so the
# eval-based indirection isn't needed.
$script:PO_TABLE_CHARS = @{
    standard = @{ TL = '╔'; TR = '╗'; BL = '╚'; BR = '╝'; H = '═'; V = '║'; VH = '╬'; VL = '╣'; VR = '╠'; HT = '╦'; HB = '╩' }
    rounded  = @{ TL = '╭'; TR = '╮'; BL = '╰'; BR = '╯'; H = '─'; V = '│'; VH = '┼'; VL = '┤'; VR = '├'; HT = '┬'; HB = '┴' }
    double   = @{ TL = '╔'; TR = '╗'; BL = '╚'; BR = '╝'; H = '═'; V = '║'; VH = '╬'; VL = '╣'; VR = '╠'; HT = '╦'; HB = '╩' }
    simple   = @{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|'; VH = '+'; VL = '+'; VR = '+'; HT = '+'; HB = '+' }
}

# ============================================================================
# Utility Functions
# ============================================================================

# Get display length (accounting for emojis and ANSI codes)
# Usage: Measure-PoshUITableTextInternal "text"
function Measure-PoshUITableTextInternal {
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return 0 }
    Measure-PoshUITextWidthInternal $Text
}

# Pad text to width with alignment
# Usage: Format-PoshUITableCellInternal "text" width alignment
function Format-PoshUITableCellInternal {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Width,
        [string]$Align = 'left'
    )

    $displayLen = Measure-PoshUITableTextInternal $Text
    $padding = $Width - $displayLen
    if ($padding -lt 0) { $padding = 0 }

    switch ($Align) {
        'right' {
            (' ' * $padding) + $Text
        }
        'center' {
            $leftPad = [math]::Floor($padding / 2)
            $rightPad = $padding - $leftPad
            (' ' * $leftPad) + $Text + (' ' * $rightPad)
        }
        default {
            $Text + (' ' * $padding)
        }
    }
}

# Get a style's box-drawing character by name (TL, TR, BL, BR, H, V, VH, VL, VR, HT, HB)
# Usage: Get-PoshUITableCharactersInternal <style> <char_name>
function Get-PoshUITableCharactersInternal {
    param([string]$Style, [string]$CharName)

    if ($Style -eq 'minimal') { return '' }
    if ($script:PO_TABLE_CHARS.ContainsKey($Style)) {
        return $script:PO_TABLE_CHARS[$Style][$CharName]
    }
    return $script:PO_TABLE_CHARS['standard'][$CharName]
}

function Get-PoshUITableInstanceWidthsInternal {
    param([Parameter(Mandatory)][psobject]$Table)

    $widths = @()
    for ($i = 0; $i -lt $Table.Headers.Count; $i++) {
        $widths += (Measure-PoshUITableTextInternal ([string]$Table.Headers[$i]))
    }

    foreach ($row in $Table.Rows) {
        for ($i = 0; $i -lt $row.Count; $i++) {
            $cellLength = Measure-PoshUITableTextInternal ([string]$row[$i])
            while ($widths.Count -le $i) { $widths += 0 }
            if ($cellLength -gt $widths[$i]) { $widths[$i] = $cellLength }
        }
    }

    for ($i = 0; $i -lt $widths.Count; $i++) {
        $widths[$i] += $Table.Padding * 2
    }
    $widths
}

function Format-PoshUITableInstanceLineInternal {
    param(
        [Parameter(Mandatory)][psobject]$Table,
        [Parameter(Mandatory)][int[]]$Widths,
        [Parameter(Mandatory)][ValidateSet('top', 'middle', 'bottom')][string]$Position,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Color
    )

    if ($Table.Style -eq 'minimal') { return $null }

    $characters = switch ($Position) {
        'top' { @('TL', 'TR', 'HT') }
        'middle' { @('VR', 'VL', 'VH') }
        'bottom' { @('BL', 'BR', 'HB') }
    }
    $horizontal = Get-PoshUITableCharactersInternal $Table.Style 'H'
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append($Color).Append((Get-PoshUITableCharactersInternal $Table.Style $characters[0]))
    for ($i = 0; $i -lt $Widths.Count; $i++) {
        [void]$builder.Append($horizontal * $Widths[$i])
        if ($i -lt $Widths.Count - 1) {
            [void]$builder.Append((Get-PoshUITableCharactersInternal $Table.Style $characters[2]))
        }
    }
    [void]$builder.Append((Get-PoshUITableCharactersInternal $Table.Style $characters[1])).Append($script:PoshUIStyle.Reset)
    $builder.ToString()
}

function Format-PoshUITableInstanceRowInternal {
    param(
        [Parameter(Mandatory)][psobject]$Table,
        [Parameter(Mandatory)][int[]]$Widths,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Cells,
        [AllowEmptyString()][string]$Color = ''
    )

    $vertical = if ($Table.Style -eq 'minimal') { ' ' } else { Get-PoshUITableCharactersInternal $Table.Style 'V' }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append($script:PoshUIStyle.TableBorder).Append($vertical).Append($script:PoshUIStyle.Reset)
    for ($i = 0; $i -lt $Widths.Count; $i++) {
        $alignment = if ($i -lt $Table.Alignments.Count -and $Table.Alignments[$i]) {
            $Table.Alignments[$i]
        }
        else {
            'left'
        }
        $cell = if ($i -lt $Cells.Count) { [string]$Cells[$i] } else { '' }
        $padded = Format-PoshUITableCellInternal "${Color}${cell}$($script:PoshUIStyle.Reset)" ($Widths[$i] - 2) $alignment
        [void]$builder.Append(" $padded ")
        [void]$builder.Append($script:PoshUIStyle.TableBorder).Append($vertical).Append($script:PoshUIStyle.Reset)
    }
    $builder.ToString()
}

# ============================================================================
# PowerShell-native Table API
# ============================================================================

function New-PoshUITable {
    <#
    .SYNOPSIS
    Creates an independent PoshUI table.
    .DESCRIPTION
    Returns a mutable table instance whose state is isolated from every other
    table instance. The object can be passed to the other PoshUI table commands.
    .PARAMETER Style
    Selects the table border style.
    .PARAMETER Header
    Sets the initial column headers.
    .PARAMETER Padding
    Sets the number of spaces on each side of a cell value.
    .EXAMPLE
    $table = New-PoshUITable -Style Rounded -Header Name, Status
    .EXAMPLE
    $table = New-PoshUITable -Style Minimal -Header Command, Duration
    .EXAMPLE
    $table = New-PoshUITable -Padding 2
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('standard', 'rounded', 'double', 'simple', 'minimal')]
        [string]$Style = [string]$script:PoshUITableConfiguration.Style,

        [AllowEmptyCollection()]
        [string[]]$Header = @(),

        [ValidateRange(0, 20)]
        [int]$Padding = [int]$script:PoshUITableConfiguration.Padding
    )

    $table = [pscustomobject]@{
        Style = $Style.ToLowerInvariant()
        Headers = [string[]]@($Header)
        Rows = [object[]]@()
        Alignments = [string[]](@('left') * $Header.Count)
        Padding = $Padding
    }
    $table.PSObject.TypeNames.Insert(0, 'PoshUI.Table')
    $table
}

function Set-PoshUITableHeader {
    <#
    .SYNOPSIS
    Replaces the headers of a PoshUI table.
    .DESCRIPTION
    Updates one table instance and resets its column alignments to left.
    .PARAMETER Table
    The table returned by New-PoshUITable.
    .PARAMETER Header
    The ordered header labels.
    .PARAMETER PassThru
    Returns the updated table instance.
    .EXAMPLE
    Set-PoshUITableHeader -Table $table -Header Name, Value
    .EXAMPLE
    $table | Set-PoshUITableHeader -Header Service, Status
    .EXAMPLE
    Set-PoshUITableHeader $table Name, Value -PassThru
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory table model.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('PoshUI.Table')][psobject]$Table,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyCollection()][string[]]$Header,

        [switch]$PassThru
    )

    $Table.Headers = [string[]]@($Header)
    $Table.Alignments = [string[]](@('left') * $Header.Count)
    if ($PassThru) { $Table }
}

function Add-PoshUITableRow {
    <#
    .SYNOPSIS
    Adds values or pipeline objects to a PoshUI table.
    .DESCRIPTION
    Adds one row for each invocation. In the Values parameter set, each value
    becomes a cell. In the InputObject parameter set, properties are projected
    in the requested order, or in header order when Property is omitted.
    .PARAMETER Table
    The table returned by New-PoshUITable.
    .PARAMETER Values
    The ordered cell values for one row.
    .PARAMETER InputObject
    An object received from the pipeline or supplied directly.
    .PARAMETER Property
    Property names to project from InputObject. Defaults to the table headers.
    .PARAMETER PassThru
    Returns the updated table instance.
    .EXAMPLE
    Add-PoshUITableRow -Table $table -Values 'api', 'healthy'
    .EXAMPLE
    $services | Add-PoshUITableRow -Table $table -Property Name, Status
    .EXAMPLE
    Add-PoshUITableRow -Table $table -Values 'worker', 'queued' -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName = 'Values')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('PoshUI.Table')][psobject]$Table,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Values')]
        [AllowEmptyCollection()][AllowNull()][object[]]$Values,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [AllowNull()][psobject]$InputObject,

        [Parameter(ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()][string[]]$Property,

        [switch]$PassThru
    )

    process {
        $cells = if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $propertyNames = if ($Property) { $Property } else { [string[]]$Table.Headers }
            @($propertyNames | ForEach-Object { $InputObject.$_ })
        }
        else {
            @($Values)
        }
        $Table.Rows = [object[]]@($Table.Rows) + ,([object[]]$cells)
        if ($PassThru) { $Table }
    }
}

function Set-PoshUITableAlignment {
    <#
    .SYNOPSIS
    Sets the alignment of a table column.
    .DESCRIPTION
    Updates the selected column without affecting other table instances.
    .PARAMETER Table
    The table returned by New-PoshUITable.
    .PARAMETER Column
    The zero-based column index.
    .PARAMETER Alignment
    The left, right, or center alignment to apply.
    .PARAMETER PassThru
    Returns the updated table instance.
    .EXAMPLE
    Set-PoshUITableAlignment -Table $table -Column 1 -Alignment Right
    .EXAMPLE
    $table | Set-PoshUITableAlignment -Column 0 -Alignment Center
    .EXAMPLE
    Set-PoshUITableAlignment $table 2 Left -PassThru
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory table model.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('PoshUI.Table')][psobject]$Table,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange(0, [int]::MaxValue)][int]$Column,

        [Parameter(Mandatory, Position = 2)]
        [ValidateSet('left', 'right', 'center')][string]$Alignment,

        [switch]$PassThru
    )

    $alignments = @($Table.Alignments)
    while ($alignments.Count -le $Column) { $alignments += 'left' }
    $alignments[$Column] = $Alignment.ToLowerInvariant()
    $Table.Alignments = [string[]]$alignments
    if ($PassThru) { $Table }
}

function Format-PoshUITable {
    <#
    .SYNOPSIS
    Formats a PoshUI table as line strings.
    .DESCRIPTION
    Produces the complete rendered table without writing to the host or changing
    table state. Each output object is one display line.
    .PARAMETER Table
    The table returned by New-PoshUITable.
    .PARAMETER BorderColor
    ANSI prefix applied to borders.
    .PARAMETER HeaderColor
    ANSI prefix applied to header values.
    .EXAMPLE
    $lines = Format-PoshUITable -Table $table
    .EXAMPLE
    $table | Format-PoshUITable | Set-Content table.txt
    .EXAMPLE
    Format-PoshUITable -Table $table -BorderColor "`e[0;34m"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Table')][psobject]$Table,

        [AllowEmptyString()][string]$BorderColor = $script:PoshUIStyle.TableBorder,

        [AllowEmptyString()][string]$HeaderColor = $script:PoshUIStyle.TableHeader
    )

    process {
        $widths = @(Get-PoshUITableInstanceWidthsInternal $Table)
        $top = Format-PoshUITableInstanceLineInternal $Table $widths 'top' $BorderColor
        if ($null -ne $top) { if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $top } else { ConvertTo-PoshUIPlainText $top } }
        $header = Format-PoshUITableInstanceRowInternal $Table $widths ([object[]]$Table.Headers) $HeaderColor
        if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $header } else { ConvertTo-PoshUIPlainText $header }
        $middle = Format-PoshUITableInstanceLineInternal $Table $widths 'middle' $BorderColor
        if ($null -ne $middle) { if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $middle } else { ConvertTo-PoshUIPlainText $middle } }
        foreach ($row in $Table.Rows) {
            $renderedRow = Format-PoshUITableInstanceRowInternal $Table $widths ([object[]]$row)
            if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $renderedRow } else { ConvertTo-PoshUIPlainText $renderedRow }
        }
        $bottom = Format-PoshUITableInstanceLineInternal $Table $widths 'bottom' $BorderColor
        if ($null -ne $bottom) { if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $bottom } else { ConvertTo-PoshUIPlainText $bottom } }
    }
}

function Show-PoshUITable {
    <#
    .SYNOPSIS
    Writes a formatted PoshUI table through the runtime output boundary.
    .DESCRIPTION
    Formats the supplied table and sends each line to Write-PoshUIHost, which
    applies the active rich, plain, or off runtime policy.
    .PARAMETER Table
    The table returned by New-PoshUITable.
    .PARAMETER BorderColor
    ANSI prefix applied to borders.
    .PARAMETER HeaderColor
    ANSI prefix applied to header values.
    .EXAMPLE
    Show-PoshUITable -Table $table
    .EXAMPLE
    $table | Show-PoshUITable
    .EXAMPLE
    Show-PoshUITable -Table $table -HeaderColor "`e[1m"
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Table')][psobject]$Table,

        [AllowEmptyString()][string]$BorderColor = $script:PoshUIStyle.TableBorder,

        [AllowEmptyString()][string]$HeaderColor = $script:PoshUIStyle.TableHeader
    )

    process {
        Format-PoshUITable -Table $Table -BorderColor $BorderColor -HeaderColor $HeaderColor |
            ForEach-Object { Write-PoshUIHost $_ }
    }
}

Export-ModuleMember -Function @(
    'New-PoshUITable'
    'Set-PoshUITableHeader'
    'Add-PoshUITableRow'
    'Set-PoshUITableAlignment'
    'Format-PoshUITable'
    'Show-PoshUITable'
)
