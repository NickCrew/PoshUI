#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop

function Get-PoshUILayoutCodePointWidthInternal {
    param([int]$Codepoint)

    $ranges = @(
        0x1100, 0x115F; 0x2329, 0x232A; 0x2E80, 0x303E
        0x3041, 0x33FF; 0x3400, 0x4DBF; 0x4E00, 0x9FFF
        0xA000, 0xA4CF; 0xAC00, 0xD7A3; 0xF900, 0xFAFF
        0xFE10, 0xFE19; 0xFE30, 0xFE6F; 0xFF00, 0xFF60
        0xFFE0, 0xFFE6; 0x1F300, 0x1FAFF; 0x20000, 0x2FFFD
        0x30000, 0x3FFFD; 0x231A, 0x231B; 0x23E9, 0x23EC
        0x23F0, 0x23F0; 0x23F3, 0x23F3; 0x25FD, 0x25FE
        0x2614, 0x2615; 0x2648, 0x2653; 0x267F, 0x267F
        0x2693, 0x2693; 0x26A1, 0x26A1; 0x26AA, 0x26AB
        0x26BD, 0x26BE; 0x26C4, 0x26C5; 0x26CE, 0x26CE
        0x26D4, 0x26D4; 0x26EA, 0x26EA; 0x26F2, 0x26F3
        0x26F5, 0x26F5; 0x26FA, 0x26FA; 0x26FD, 0x26FD
        0x2705, 0x2705; 0x270A, 0x270B; 0x2728, 0x2728
        0x274C, 0x274C; 0x274E, 0x274E; 0x2753, 0x2755
        0x2757, 0x2757; 0x2795, 0x2797; 0x27B0, 0x27B0
        0x27BF, 0x27BF; 0x2B1B, 0x2B1C; 0x2B50, 0x2B50
        0x2B55, 0x2B55
    )

    for ($index = 0; $index -lt $ranges.Count; $index += 2) {
        if ($Codepoint -ge $ranges[$index] -and $Codepoint -le $ranges[$index + 1]) {
            return 2
        }
    }
    1
}

function Measure-PoshUILayoutTextInternal {
    param([AllowEmptyString()][string]$Text)

    $plain = ConvertTo-PoshUIPlainText $Text
    $width = 0
    $elements = [System.Globalization.StringInfo]::GetTextElementEnumerator($plain)
    while ($elements.MoveNext()) {
        $width += Get-PoshUILayoutGraphemeWidthInternal ([string]$elements.Current)
    }
    $width
}

function Get-PoshUILayoutGraphemeWidthInternal {
    param([Parameter(Mandatory)][string]$TextElement)

    $runes = @($TextElement.EnumerateRunes())
    $hasEmojiPresentation = $false
    $width = 0
    foreach ($rune in $runes) {
        $codepoint = $rune.Value
        if ($codepoint -eq 0x200D -or $codepoint -eq 0xFE0F) {
            $hasEmojiPresentation = $true
            continue
        }
        if ($codepoint -eq 0xFE0E) { continue }
        $category = [System.Text.Rune]::GetUnicodeCategory($rune)
        if ($category -in @(
            [System.Globalization.UnicodeCategory]::NonSpacingMark
            [System.Globalization.UnicodeCategory]::EnclosingMark
            [System.Globalization.UnicodeCategory]::Format
        )) { continue }
        if (($codepoint -ge 0x1F1E6 -and $codepoint -le 0x1F1FF) -or
            ($codepoint -ge 0x1F300 -and $codepoint -le 0x1FAFF)) {
            $hasEmojiPresentation = $true
        }
        $width += Get-PoshUILayoutCodePointWidthInternal $codepoint
    }

    if ($hasEmojiPresentation) { return 2 }
    $width
}

function Get-PoshUILayoutActiveSgrInternal {
    param([AllowEmptyString()][string]$Text)

    $active = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, "`e\[([0-9;]*)m")) {
        $parameters = if ($match.Groups[1].Value.Length -eq 0) {
            @(0)
        }
        else {
            @($match.Groups[1].Value -split ';' | ForEach-Object { [int]$_ })
        }
        if ($parameters -contains 0) { $active.Clear() }
        if (@($parameters | Where-Object { $_ -ne 0 }).Count -gt 0) {
            $active.Add($match.Value)
        }
    }
    $active -join ''
}

function Close-PoshUILayoutStyleInternal {
    param([AllowEmptyString()][string]$Text)

    if ((Get-PoshUILayoutActiveSgrInternal $Text).Length -gt 0) { return "$Text`e[0m" }
    $Text
}

function Resolve-PoshUILayoutWidthInternal {
    param([int]$Width, [int]$Minimum = 1)

    $resolved = $Width
    if ($resolved -eq 0) {
        $resolved = try { [Console]::WindowWidth } catch { 80 }
        if ($resolved -lt 1) { $resolved = 80 }
    }
    if ($resolved -lt $Minimum) {
        throw "Width must be at least $Minimum columns for this layout. Received $resolved."
    }
    $resolved
}

function ConvertTo-PoshUILayoutLinesInternal {
    param([AllowNull()][object[]]$InputObject)

    $lines = [System.Collections.Generic.List[string]]::new()
    $pending = [System.Collections.ArrayList]::new()
    $initial = @($InputObject)
    for ($index = $initial.Count - 1; $index -ge 0; $index--) { [void]$pending.Add($initial[$index]) }
    while ($pending.Count -gt 0) {
        $lastIndex = $pending.Count - 1
        $item = $pending[$lastIndex]
        $pending.RemoveAt($lastIndex)
        if ($null -eq $item) { $lines.Add(''); continue }
        if ($item -isnot [string] -and $item -is [System.Collections.IEnumerable]) {
            $nestedItems = @($item)
            for ($index = $nestedItems.Count - 1; $index -ge 0; $index--) { [void]$pending.Add($nestedItems[$index]) }
            continue
        }
        $text = if (Test-PoshUIRich) {
            ConvertTo-PoshUISafeRichText ([string]$item)
        }
        else {
            ConvertTo-PoshUIPlainText ([string]$item)
        }
        foreach ($line in ($text -split "`r?`n", 0, 'RegexMatch')) {
            $lines.Add($line)
        }
    }
    if ($lines.Count -eq 0) { $lines.Add('') }
    $lines.ToArray()
}

function Limit-PoshUILayoutWidthInternal {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Width
    )

    $builder = [System.Text.StringBuilder]::new()
    $visible = 0
    $offset = 0
    while ($offset -lt $Text.Length) {
        $ansi = [regex]::Match($Text.Substring($offset), '^\x1b\[[0-9;?]*[ -/]*[@-~]')
        if ($ansi.Success) {
            [void]$builder.Append($ansi.Value)
            $offset += $ansi.Length
            continue
        }

        $textElement = [System.Globalization.StringInfo]::GetNextTextElement($Text, $offset)
        $consumed = $textElement.Length
        $elementWidth = Get-PoshUILayoutGraphemeWidthInternal $textElement
        if (($visible + $elementWidth) -gt $Width) { break }
        [void]$builder.Append($textElement)
        $visible += $elementWidth
        $offset += $consumed
    }

    [pscustomobject]@{
        Text  = $builder.ToString()
        Rest  = $Text.Substring($offset)
        Width = $visible
    }
}

function Split-PoshUILayoutLineInternal {
    param([AllowEmptyString()][string]$Text, [int]$Width)

    if ($Text.Length -eq 0) { return ,'' }
    $result = [System.Collections.Generic.List[string]]::new()
    $remaining = $Text
    while ((Measure-PoshUILayoutTextInternal $remaining) -gt $Width) {
        $part = Limit-PoshUILayoutWidthInternal -Text $remaining -Width $Width
        if ($part.Width -eq 0) {
            $firstElement = [System.Globalization.StringInfo]::GetNextTextElement($part.Rest, 0)
            $activeStyle = Get-PoshUILayoutActiveSgrInternal $part.Text
            $result.Add((Close-PoshUILayoutStyleInternal "$($part.Text)…"))
            $remaining = $activeStyle + $part.Rest.Substring($firstElement.Length)
            continue
        }
        if ($part.Rest.StartsWith(' ')) {
            $candidate = $part.Text.TrimEnd()
            $activeStyle = Get-PoshUILayoutActiveSgrInternal $candidate
            $result.Add((Close-PoshUILayoutStyleInternal $candidate))
            $remaining = $activeStyle + $part.Rest.TrimStart()
            continue
        }
        $breakAt = $part.Text.LastIndexOf(' ')
        if ($breakAt -gt 0) {
            $candidate = $part.Text.Substring(0, $breakAt).TrimEnd()
            $consumedText = $part.Text.Substring(0, $breakAt + 1)
            $remaining = ($part.Text.Substring($breakAt + 1) + $part.Rest).TrimStart()
            if ($consumedText.Length -eq 0) { $remaining = $part.Rest }
            $activeStyle = Get-PoshUILayoutActiveSgrInternal $candidate
            $result.Add((Close-PoshUILayoutStyleInternal $candidate))
            $remaining = $activeStyle + $remaining
        }
        else {
            $activeStyle = Get-PoshUILayoutActiveSgrInternal $part.Text
            $result.Add((Close-PoshUILayoutStyleInternal $part.Text))
            $remaining = $activeStyle + $part.Rest
        }
    }
    if ($remaining.Length -gt 0 -or $result.Count -eq 0) {
        $result.Add($remaining)
    }
    $result.ToArray()
}

function Limit-PoshUILayoutLineInternal {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Width,
        [AllowEmptyString()][string]$Ellipsis = '…'
    )

    if ((Measure-PoshUILayoutTextInternal $Text) -le $Width) { return $Text }
    $ellipsisWidth = Measure-PoshUILayoutTextInternal $Ellipsis
    if ($ellipsisWidth -gt $Width) { return (Limit-PoshUILayoutWidthInternal $Ellipsis $Width).Text }
    $prefix = (Limit-PoshUILayoutWidthInternal $Text ($Width - $ellipsisWidth)).Text
    Close-PoshUILayoutStyleInternal "$prefix$Ellipsis"
}

function Format-PoshUILayoutLineInternal {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Width,
        [ValidateSet('Left', 'Center', 'Right')][string]$Alignment
    )

    $remaining = [Math]::Max(0, $Width - (Measure-PoshUILayoutTextInternal $Text))
    $left = switch ($Alignment) {
        'Right' { $remaining }
        'Center' { [int][Math]::Floor($remaining / 2) }
        default { 0 }
    }
    $right = $remaining - $left
    (' ' * $left) + (Close-PoshUILayoutStyleInternal $Text) + (' ' * $right)
}

function ConvertTo-PoshUILayoutTextInternal {
    param(
        [object[]]$InputObject,
        [int]$Width,
        [int]$PaddingLeft,
        [int]$PaddingRight,
        [int]$PaddingTop,
        [int]$PaddingBottom,
        [string]$HorizontalAlignment,
        [string]$Overflow,
        [string]$Ellipsis
    )

    $contentWidth = $Width - $PaddingLeft - $PaddingRight
    if ($contentWidth -lt 1) {
        throw "Width $Width leaves no content columns after horizontal padding."
    }

    $rendered = [System.Collections.Generic.List[string]]::new()
    $blank = ' ' * $Width
    1..$PaddingTop | ForEach-Object { if ($PaddingTop -gt 0) { $rendered.Add($blank) } }
    foreach ($line in ConvertTo-PoshUILayoutLinesInternal $InputObject) {
        $contentLines = if ($Overflow -eq 'Wrap') {
            @(Split-PoshUILayoutLineInternal $line $contentWidth)
        }
        else {
            @(Limit-PoshUILayoutLineInternal $line $contentWidth $Ellipsis)
        }
        foreach ($contentLine in $contentLines) {
            $aligned = Format-PoshUILayoutLineInternal $contentLine $contentWidth $HorizontalAlignment
            $rendered.Add((' ' * $PaddingLeft) + $aligned + (' ' * $PaddingRight))
        }
    }
    1..$PaddingBottom | ForEach-Object { if ($PaddingBottom -gt 0) { $rendered.Add($blank) } }

    [pscustomobject]@{
        PSTypeName = 'PoshUI.RenderModel'
        Width      = $Width
        Height     = $rendered.Count
        Lines      = [string[]]$rendered.ToArray()
    }
}

function Write-PoshUILayoutLinesInternal {
    param([string[]]$Lines)
    $runtime = Get-PoshUIRuntime
    foreach ($line in $Lines) {
        if ($runtime.Mode -eq 'rich') { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
    }
}

function Format-PoshUIText {
    <#
    .SYNOPSIS
    Formats text within a terminal-width-aware rectangular area.
    .DESCRIPTION
    Wraps or truncates input, applies horizontal alignment and padding, and
    returns fixed-width lines without writing to the terminal.
    .PARAMETER InputObject
    Text or formatted component lines to arrange. Pipeline input is accepted.
    .PARAMETER Width
    Output width. Zero resolves the current terminal width with an 80-column fallback.
    .PARAMETER PaddingLeft
    Blank columns added at the left edge.
    .PARAMETER PaddingRight
    Blank columns added at the right edge.
    .PARAMETER PaddingTop
    Blank lines added above the content.
    .PARAMETER PaddingBottom
    Blank lines added below the content.
    .PARAMETER HorizontalAlignment
    Left, Center, or Right alignment within the content area.
    .PARAMETER Overflow
    Wrap long input onto more lines or truncate it with Ellipsis.
    .PARAMETER Ellipsis
    Marker used when Overflow is Truncate.
    .EXAMPLE
    Format-PoshUIText -InputObject 'ready' -Width 9 -HorizontalAlignment Center
    .EXAMPLE
    'alpha beta' | Format-PoshUIText -Width 6 -Overflow Wrap
    .EXAMPLE
    Format-PoshUIText 'deployment' -Width 6 -Overflow Truncate -Ellipsis '...'
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()][object]$InputObject,
        [Parameter(Position = 1)][ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$PaddingLeft = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$PaddingRight = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$PaddingTop = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$PaddingBottom = 0,
        [ValidateSet('Left', 'Center', 'Right')][string]$HorizontalAlignment = 'Left',
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Wrap',
        [AllowEmptyString()][string]$Ellipsis = '…'
    )
    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        $resolved = Resolve-PoshUILayoutWidthInternal $Width ($PaddingLeft + $PaddingRight + 1)
        $model = ConvertTo-PoshUILayoutTextInternal $items.ToArray() $resolved $PaddingLeft $PaddingRight $PaddingTop $PaddingBottom $HorizontalAlignment $Overflow $Ellipsis
        Write-PoshUILayoutLinesInternal $model.Lines
    }
}

function Format-PoshUIPanel {
    <#
    .SYNOPSIS
    Formats content inside a terminal-width-aware panel.
    .DESCRIPTION
    Builds a complete panel render model before returning its border and content lines.
    .PARAMETER InputObject
    Text or formatted component lines placed inside the panel.
    .PARAMETER Title
    Optional panel title displayed in the top border.
    .PARAMETER Width
    Total panel width. Zero resolves the terminal width.
    .PARAMETER Padding
    Horizontal padding inside the panel.
    .PARAMETER HorizontalAlignment
    Content alignment inside the panel.
    .PARAMETER Overflow
    Wrap or Truncate behavior for content wider than the panel.
    .PARAMETER BorderStyle
    Rounded, Square, Ascii, or None.
    .EXAMPLE
    Format-PoshUIPanel -Title Status -InputObject Ready -Width 16
    .EXAMPLE
    'one', 'two' | Format-PoshUIPanel -BorderStyle Ascii -Width 12
    .EXAMPLE
    Format-PoshUIPanel (Format-PoshUIGauge 2 4) -Width 30
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()][object]$InputObject,
        [AllowEmptyString()][string]$Title = '',
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Padding = 1,
        [ValidateSet('Left', 'Center', 'Right')][string]$HorizontalAlignment = 'Left',
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Wrap',
        [ValidateSet('Rounded', 'Square', 'Ascii', 'None')][string]$BorderStyle = 'Rounded'
    )
    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        $borderWidth = if ($BorderStyle -eq 'None') { 0 } else { 2 }
        $resolved = Resolve-PoshUILayoutWidthInternal $Width ($borderWidth + (2 * $Padding) + 1)
        $innerWidth = $resolved - $borderWidth
        $content = ConvertTo-PoshUILayoutTextInternal $items.ToArray() $innerWidth $Padding $Padding 0 0 $HorizontalAlignment $Overflow '…'
        if ($BorderStyle -eq 'None') { Write-PoshUILayoutLinesInternal $content.Lines; return }

        $characters = switch ($BorderStyle) {
            'Square' { @{ TL = '┌'; TR = '┐'; BL = '└'; BR = '┘'; H = '─'; V = '│' } }
            'Ascii'  { @{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|' } }
            default  { @{ TL = '╭'; TR = '╮'; BL = '╰'; BR = '╯'; H = '─'; V = '│' } }
        }
        $topContent = $characters.H * ($resolved - 2)
        if ($Title) {
            $label = Limit-PoshUILayoutLineInternal " $Title " ($resolved - 2) '…'
            $topContent = $label + ($characters.H * [Math]::Max(0, ($resolved - 2) - (Measure-PoshUILayoutTextInternal $label)))
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("$($characters.TL)$topContent$($characters.TR)")
        foreach ($line in $content.Lines) { $lines.Add("$($characters.V)$line$($characters.V)") }
        $lines.Add("$($characters.BL)$($characters.H * ($resolved - 2))$($characters.BR)")
        Write-PoshUILayoutLinesInternal $lines.ToArray()
    }
}

function Show-PoshUIPanel {
    <#
    .SYNOPSIS
    Displays a terminal-width-aware panel.
    .DESCRIPTION
    Formats a panel, then writes its completed render model through the shared Runtime boundary.
    .PARAMETER InputObject
    Text or component lines placed inside the panel.
    .PARAMETER Title
    Optional title in the top border.
    .PARAMETER Width
    Total panel width. Zero resolves the terminal width.
    .PARAMETER Padding
    Horizontal padding inside the panel.
    .PARAMETER HorizontalAlignment
    Left, Center, or Right content alignment.
    .PARAMETER Overflow
    Wrap or Truncate behavior for long content.
    .PARAMETER BorderStyle
    Rounded, Square, Ascii, or None.
    .EXAMPLE
    Show-PoshUIPanel -Title Status -InputObject Ready -Width 16
    .EXAMPLE
    'one', 'two' | Show-PoshUIPanel -BorderStyle Ascii
    .EXAMPLE
    Show-PoshUIPanel (Format-PoshUISparkline 1,2,3) -Width 24
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][AllowNull()][object]$InputObject,
        [AllowEmptyString()][string]$Title = '',
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Padding = 1,
        [ValidateSet('Left', 'Center', 'Right')][string]$HorizontalAlignment = 'Left',
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Wrap',
        [ValidateSet('Rounded', 'Square', 'Ascii', 'None')][string]$BorderStyle = 'Rounded'
    )
    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        Format-PoshUIPanel -InputObject $items.ToArray() -Title $Title -Width $Width -Padding $Padding -HorizontalAlignment $HorizontalAlignment -Overflow $Overflow -BorderStyle $BorderStyle |
            ForEach-Object { Write-PoshUIHost $_ }
    }
}

function ConvertTo-PoshUILayoutBlocksInternal {
    param([object[]]$Block)
    $blocks = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Block)) {
        $lines = if ($item -is [string]) {
            @([string]$item)
        }
        elseif ($item.PSObject.Properties.Name -contains 'Lines') {
            @($item.Lines | ForEach-Object { [string]$_ })
        }
        else {
            @($item | ForEach-Object { [string]$_ })
        }
        $blocks.Add([pscustomobject]@{ Lines = [string[]]$lines })
    }
    $blocks.ToArray()
}

function Format-PoshUIStack {
    <#
    .SYNOPSIS
    Formats component blocks as a vertical stack.
    .DESCRIPTION
    Normalizes each block into lines, optionally constrains its width, and inserts a stable vertical gap.
    .PARAMETER Block
    Component blocks. Each block may be a string or an array of formatted lines.
    .PARAMETER Width
    Stack width. Zero uses the widest input block.
    .PARAMETER Gap
    Blank lines inserted between blocks.
    .PARAMETER HorizontalAlignment
    Alignment of each block inside the stack width.
    .EXAMPLE
    Format-PoshUIStack -Block @('one', 'two') -Gap 1
    .EXAMPLE
    Format-PoshUIStack -Block @($panel, $table) -Width 80
    .EXAMPLE
    $lines = Format-PoshUIStack @('a', 'b') -HorizontalAlignment Right
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Block,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Gap = 0,
        [ValidateSet('Left', 'Center', 'Right')][string]$HorizontalAlignment = 'Left'
    )
    $blocks = ConvertTo-PoshUILayoutBlocksInternal $Block
    if ($Width -eq 0) {
        $Width = [Math]::Max(1, [int](($blocks.Lines | ForEach-Object { $_ } | ForEach-Object { Measure-PoshUILayoutTextInternal $_ } | Measure-Object -Maximum).Maximum))
    }
    $Width = Resolve-PoshUILayoutWidthInternal $Width
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $blocks.Count; $index++) {
        if ($index -gt 0) { 1..$Gap | ForEach-Object { if ($Gap -gt 0) { $lines.Add(' ' * $Width) } } }
        foreach ($line in $blocks[$index].Lines) {
            $fitted = Limit-PoshUILayoutLineInternal $line $Width '…'
            $lines.Add((Format-PoshUILayoutLineInternal $fitted $Width $HorizontalAlignment))
        }
    }
    Write-PoshUILayoutLinesInternal $lines.ToArray()
}

function Show-PoshUIStack {
    <#
    .SYNOPSIS
    Displays component blocks as a vertical stack.
    .DESCRIPTION
    Formats the full stack first, then sends each line through the Runtime display boundary.
    .PARAMETER Block
    Component blocks to stack.
    .PARAMETER Width
    Stack width. Zero uses the widest input block.
    .PARAMETER Gap
    Blank lines between blocks.
    .PARAMETER HorizontalAlignment
    Block alignment within the stack.
    .EXAMPLE
    Show-PoshUIStack -Block @('one', 'two')
    .EXAMPLE
    Show-PoshUIStack -Block @($panel, $chart) -Gap 1
    .EXAMPLE
    Show-PoshUIStack @('a', 'b') -Width 20 -HorizontalAlignment Center
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Block,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Gap = 0,
        [ValidateSet('Left', 'Center', 'Right')][string]$HorizontalAlignment = 'Left'
    )
    Format-PoshUIStack @PSBoundParameters | ForEach-Object { Write-PoshUIHost $_ }
}

function Format-PoshUIColumn {
    <#
    .SYNOPSIS
    Formats component blocks beside each other as columns.
    .DESCRIPTION
    Allocates available width across columns, fits every input line, and returns one completed line model.
    .PARAMETER Column
    Component blocks to place beside each other.
    .PARAMETER Width
    Total width. Zero resolves the terminal width.
    .PARAMETER Gap
    Blank columns between components.
    .PARAMETER ColumnWidth
    Optional explicit width for each column.
    .EXAMPLE
    Format-PoshUIColumn -Column @('left', 'right') -Width 20
    .EXAMPLE
    Format-PoshUIColumn -Column @($table, $chart) -Gap 2
    .EXAMPLE
    $lines = Format-PoshUIColumn @('a', 'b') -ColumnWidth 4,8 -Width 13
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Column,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Gap = 1,
        [int[]]$ColumnWidth
    )
    $blocks = ConvertTo-PoshUILayoutBlocksInternal $Column
    $resolved = Resolve-PoshUILayoutWidthInternal $Width ($blocks.Count + ($Gap * [Math]::Max(0, $blocks.Count - 1)))
    $available = $resolved - ($Gap * [Math]::Max(0, $blocks.Count - 1))
    if ($ColumnWidth) {
        if ($ColumnWidth.Count -ne $blocks.Count) { throw 'ColumnWidth must contain one width for each column.' }
        if (@($ColumnWidth | Where-Object { $_ -lt 1 }).Count -gt 0) { throw 'Every ColumnWidth value must be at least 1.' }
        if (($ColumnWidth | Measure-Object -Sum).Sum -ne $available) { throw "ColumnWidth values must total $available columns after gaps." }
        $widths = [int[]]$ColumnWidth
    }
    else {
        $base = [int][Math]::Floor($available / $blocks.Count)
        $remainder = $available % $blocks.Count
        $widths = [int[]](0..($blocks.Count - 1) | ForEach-Object { $base + $(if ($_ -lt $remainder) { 1 } else { 0 }) })
    }
    $height = [int](($blocks | ForEach-Object { $_.Lines.Count } | Measure-Object -Maximum).Maximum)
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($row = 0; $row -lt $height; $row++) {
        $parts = for ($columnIndex = 0; $columnIndex -lt $blocks.Count; $columnIndex++) {
            $text = if ($row -lt $blocks[$columnIndex].Lines.Count) { $blocks[$columnIndex].Lines[$row] } else { '' }
            $text = Limit-PoshUILayoutLineInternal $text $widths[$columnIndex] '…'
            Format-PoshUILayoutLineInternal $text $widths[$columnIndex] 'Left'
        }
        $lines.Add($parts -join (' ' * $Gap))
    }
    Write-PoshUILayoutLinesInternal $lines.ToArray()
}

function Show-PoshUIColumn {
    <#
    .SYNOPSIS
    Displays component blocks beside each other as columns.
    .DESCRIPTION
    Formats all columns before writing their lines through the Runtime boundary.
    .PARAMETER Column
    Component blocks to place beside each other.
    .PARAMETER Width
    Total output width. Zero resolves the terminal width.
    .PARAMETER Gap
    Blank columns between components.
    .PARAMETER ColumnWidth
    Optional explicit width for each column.
    .EXAMPLE
    Show-PoshUIColumn -Column @('left', 'right') -Width 20
    .EXAMPLE
    Show-PoshUIColumn -Column @($panel, $table) -Gap 2
    .EXAMPLE
    Show-PoshUIColumn @('a', 'b') -ColumnWidth 4,8 -Width 13
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Column,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$Gap = 1,
        [int[]]$ColumnWidth
    )
    Format-PoshUIColumn @PSBoundParameters | ForEach-Object { Write-PoshUIHost $_ }
}

function Format-PoshUIGrid {
    <#
    .SYNOPSIS
    Formats component blocks into a terminal-width-aware grid.
    .DESCRIPTION
    Arranges cells in row-major order, sizes each row to its tallest cell, and returns stable lines.
    .PARAMETER Cell
    Component blocks arranged in row-major order.
    .PARAMETER Columns
    Number of cells in each grid row.
    .PARAMETER Width
    Total grid width. Zero resolves the terminal width.
    .PARAMETER ColumnGap
    Blank columns between grid cells.
    .PARAMETER RowGap
    Blank lines between grid rows.
    .EXAMPLE
    Format-PoshUIGrid -Cell @('a', 'b', 'c', 'd') -Columns 2 -Width 9
    .EXAMPLE
    Format-PoshUIGrid -Cell @($panel, $table, $chart) -Columns 2
    .EXAMPLE
    $lines = Format-PoshUIGrid @('one', 'two') -Columns 1 -RowGap 1
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Cell,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Columns,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$ColumnGap = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$RowGap = 0
    )
    $blocks = ConvertTo-PoshUILayoutBlocksInternal $Cell
    $resolved = Resolve-PoshUILayoutWidthInternal $Width ($Columns + ($ColumnGap * [Math]::Max(0, $Columns - 1)))
    $available = $resolved - ($ColumnGap * [Math]::Max(0, $Columns - 1))
    $base = [int][Math]::Floor($available / $Columns)
    $remainder = $available % $Columns
    $widths = [int[]](0..($Columns - 1) | ForEach-Object { $base + $(if ($_ -lt $remainder) { 1 } else { 0 }) })
    $output = [System.Collections.Generic.List[string]]::new()
    $rowCount = [int][Math]::Ceiling($blocks.Count / [double]$Columns)
    for ($gridRow = 0; $gridRow -lt $rowCount; $gridRow++) {
        if ($gridRow -gt 0) { 1..$RowGap | ForEach-Object { if ($RowGap -gt 0) { $output.Add(' ' * $resolved) } } }
        $rowBlocks = for ($columnIndex = 0; $columnIndex -lt $Columns; $columnIndex++) {
            $cellIndex = ($gridRow * $Columns) + $columnIndex
            if ($cellIndex -lt $blocks.Count) { $blocks[$cellIndex] } else { [pscustomobject]@{ Lines = [string[]]@('') } }
        }
        $height = [int](($rowBlocks | ForEach-Object { $_.Lines.Count } | Measure-Object -Maximum).Maximum)
        for ($lineIndex = 0; $lineIndex -lt $height; $lineIndex++) {
            $parts = for ($columnIndex = 0; $columnIndex -lt $Columns; $columnIndex++) {
                $text = if ($lineIndex -lt $rowBlocks[$columnIndex].Lines.Count) { $rowBlocks[$columnIndex].Lines[$lineIndex] } else { '' }
                $text = Limit-PoshUILayoutLineInternal $text $widths[$columnIndex] '…'
                Format-PoshUILayoutLineInternal $text $widths[$columnIndex] 'Left'
            }
            $output.Add($parts -join (' ' * $ColumnGap))
        }
    }
    Write-PoshUILayoutLinesInternal $output.ToArray()
}

function Show-PoshUIGrid {
    <#
    .SYNOPSIS
    Displays component blocks in a terminal-width-aware grid.
    .DESCRIPTION
    Builds the complete grid first, then writes its stable lines through Runtime.
    .PARAMETER Cell
    Component blocks arranged in row-major order.
    .PARAMETER Columns
    Number of cells in each row.
    .PARAMETER Width
    Total grid width. Zero resolves the terminal width.
    .PARAMETER ColumnGap
    Blank columns between cells.
    .PARAMETER RowGap
    Blank lines between rows.
    .EXAMPLE
    Show-PoshUIGrid -Cell @('a', 'b', 'c', 'd') -Columns 2 -Width 9
    .EXAMPLE
    Show-PoshUIGrid -Cell @($panel, $table) -Columns 2
    .EXAMPLE
    Show-PoshUIGrid @('one', 'two') -Columns 1 -RowGap 1
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][object[]]$Cell,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Columns,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateRange(0, [int]::MaxValue)][int]$ColumnGap = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$RowGap = 0
    )
    Format-PoshUIGrid @PSBoundParameters | ForEach-Object { Write-PoshUIHost $_ }
}

Export-ModuleMember -Function @(
    'Format-PoshUIText'
    'Format-PoshUIPanel'
    'Show-PoshUIPanel'
    'Format-PoshUIStack'
    'Show-PoshUIStack'
    'Format-PoshUIColumn'
    'Show-PoshUIColumn'
    'Format-PoshUIGrid'
    'Show-PoshUIGrid'
)
