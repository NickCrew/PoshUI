#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop

function ConvertTo-PoshUITextLine {
    param([AllowEmptyCollection()][string[]]$Text)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($part in $Text) {
        foreach ($line in [regex]::Split($(if ($null -eq $part) { '' } else { $part }), "\r\n|\n|\r")) {
            $lines.Add($line)
        }
    }
    $lines.ToArray()
}

function Get-PoshUITextElementWidth {
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
        if ($codepoint -ge 0x1F1E6 -and $codepoint -le 0x1FAFF) { $emoji = $true }
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

function Measure-PoshUITextWidth {
    param([AllowEmptyString()][string]$Text)
    $plain = ConvertTo-PoshUIPlainText $Text
    $width = 0
    $elements = [System.Globalization.StringInfo]::GetTextElementEnumerator($plain)
    while ($elements.MoveNext()) { $width += Get-PoshUITextElementWidth ([string]$elements.Current) }
    $width
}

function Get-PoshUITextActiveSgr {
    param([AllowEmptyString()][string]$Text)
    $active = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, "`e\[([0-9;]*)m")) {
        $values = if ($match.Groups[1].Value) { @($match.Groups[1].Value -split ';' | ForEach-Object { [int]$_ }) } else { @(0) }
        if ($values -contains 0) { $active.Clear() }
        if (@($values | Where-Object { $_ -ne 0 }).Count -gt 0) { $active.Add($match.Value) }
    }
    $active -join ''
}

function Split-PoshUITextWidth {
    param([AllowEmptyString()][string]$Text, [int]$Width)
    if ($Width -le 0) { return ,$Text }
    @(
        Format-PoshUIText -InputObject $Text -Width $Width -Overflow Wrap |
            ForEach-Object { $_.TrimEnd() }
    )
}

function ConvertTo-PoshUITextRender {
    param([AllowEmptyString()][string]$Text)
    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $Text } else { ConvertTo-PoshUIPlainText $Text }
}

function Format-PoshUICodeBlock {
    <#
    .SYNOPSIS
    Formats source text as a stable code block
    .DESCRIPTION
    Returns source lines with optional one-based line numbers and deterministic
    hard wrapping. Embedded newlines are preserved structurally as distinct
    output lines. The command does not write to the host or depend on color.
    .PARAMETER Text
    Source text or lines. Accepts pipeline input.
    .PARAMETER StartLine
    Number assigned to the first source line.
    .PARAMETER Width
    Maximum content width. Zero disables wrapping.
    .PARAMETER NoLineNumbers
    Omits the line-number gutter.
    .INPUTS
    System.String
    .OUTPUTS
    System.String
    .EXAMPLE
    Format-PoshUICodeBlock -Text 'Get-Process'

    Formats one numbered source line.
    .EXAMPLE
    Get-Content script.ps1 | Format-PoshUICodeBlock -StartLine 20

    Formats pipeline text beginning at line 20.
    .EXAMPLE
    Format-PoshUICodeBlock -Text $source -Width 40 -NoLineNumbers

    Returns wrapped source without a number gutter.
    .NOTES
    Wrapping counts terminal display columns and preserves ANSI and grapheme boundaries.
    .LINK
    Show-PoshUICodeBlock
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Text,
        [ValidateRange(1, [int]::MaxValue)][int]$StartLine = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [switch]$NoLineNumbers
    )
    begin { $parts = [System.Collections.Generic.List[string]]::new() }
    process { $parts.Add($Text) }
    end {
        $lines = @(ConvertTo-PoshUITextLine $parts.ToArray())
        $numberWidth = ([string]($StartLine + [Math]::Max(0, $lines.Count - 1))).Length
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $wrapped = @(Split-PoshUITextWidth -Text $lines[$index] -Width $Width)
            for ($partIndex = 0; $partIndex -lt $wrapped.Count; $partIndex++) {
                if ($NoLineNumbers) { ConvertTo-PoshUITextRender $wrapped[$partIndex]; continue }
                $number = if ($partIndex -eq 0) { [string]($StartLine + $index) } else { '' }
                ConvertTo-PoshUITextRender ($number.PadLeft($numberWidth) + ' | ' + $wrapped[$partIndex])
            }
        }
    }
}

function Show-PoshUICodeBlock {
    <#
    .SYNOPSIS
    Displays source text as a stable code block
    .DESCRIPTION
    Formats source text with Format-PoshUICodeBlock and writes every line
    through the shared PoshUI host boundary.
    .PARAMETER Text
    Source text or lines. Accepts pipeline input.
    .PARAMETER StartLine
    Number assigned to the first source line.
    .PARAMETER Width
    Maximum content width. Zero disables wrapping.
    .PARAMETER NoLineNumbers
    Omits the line-number gutter.
    .INPUTS
    System.String
    .OUTPUTS
    None
    .EXAMPLE
    Show-PoshUICodeBlock -Text 'Get-Process'

    Displays one numbered source line.
    .EXAMPLE
    Get-Content script.ps1 | Show-PoshUICodeBlock -Width 80

    Displays wrapped source from the pipeline.
    .EXAMPLE
    Show-PoshUICodeBlock -Text $source -NoLineNumbers

    Displays source without line numbers.
    .NOTES
    Off mode suppresses host output through Write-PoshUIHost.
    .LINK
    Format-PoshUICodeBlock
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Text,
        [ValidateRange(1, [int]::MaxValue)][int]$StartLine = 1,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [switch]$NoLineNumbers
    )
    begin { $parts = [System.Collections.Generic.List[string]]::new() }
    process { $parts.Add($Text) }
    end {
        foreach ($line in @($parts.ToArray() | Format-PoshUICodeBlock -StartLine $StartLine -Width $Width -NoLineNumbers:$NoLineNumbers)) {
            Write-PoshUIHost $line
        }
    }
}

function Format-PoshUIDiff {
    <#
    .SYNOPSIS
    Formats a line-oriented text diff
    .DESCRIPTION
    Computes a longest-common-subsequence diff and emits context, removal, and
    addition lines. Every state has a stable leading marker, so meaning never
    depends on color. Optional wrapping retains that marker on continuations.
    .PARAMETER OldText
    Original text or lines.
    .PARAMETER NewText
    Replacement text or lines.
    .PARAMETER ContextLines
    Unchanged lines retained around changes. Use zero for changed lines only.
    .PARAMETER Width
    Maximum content width. Zero disables wrapping.
    .PARAMETER NoLineNumbers
    Omits old and new line-number gutters but retains state markers.
    .INPUTS
    None
    .OUTPUTS
    System.String
    .EXAMPLE
    Format-PoshUIDiff -OldText 'old' -NewText 'new'

    Returns one removal and one addition.
    .EXAMPLE
    Format-PoshUIDiff -OldText $before -NewText $after -ContextLines 1

    Retains one unchanged line around each change.
    .EXAMPLE
    Format-PoshUIDiff -OldText $before -NewText $after -Width 60 -NoLineNumbers

    Returns wrapped marker-only diff lines.
    .NOTES
    The algorithm is intended for terminal-sized text, not very large files.
    .LINK
    Show-PoshUIDiff
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OldText,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NewText,
        [ValidateRange(0, [int]::MaxValue)][int]$ContextLines = 3,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [switch]$NoLineNumbers
    )

    $oldLines = @(ConvertTo-PoshUITextLine $OldText)
    $newLines = @(ConvertTo-PoshUITextLine $NewText)
    $matrix = [int[,]]::new($oldLines.Count + 1, $newLines.Count + 1)
    for ($oldIndex = $oldLines.Count - 1; $oldIndex -ge 0; $oldIndex--) {
        for ($newIndex = $newLines.Count - 1; $newIndex -ge 0; $newIndex--) {
            $matrix[$oldIndex, $newIndex] = if ($oldLines[$oldIndex] -ceq $newLines[$newIndex]) {
                1 + $matrix[($oldIndex + 1), ($newIndex + 1)]
            }
            else { [Math]::Max($matrix[($oldIndex + 1), $newIndex], $matrix[$oldIndex, ($newIndex + 1)]) }
        }
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $oldIndex = 0; $newIndex = 0; $oldNumber = 1; $newNumber = 1
    while ($oldIndex -lt $oldLines.Count -or $newIndex -lt $newLines.Count) {
        if ($oldIndex -lt $oldLines.Count -and $newIndex -lt $newLines.Count -and $oldLines[$oldIndex] -ceq $newLines[$newIndex]) {
            $records.Add([pscustomobject]@{ Kind = ' '; Old = $oldNumber; New = $newNumber; Text = $oldLines[$oldIndex] })
            $oldIndex++; $newIndex++; $oldNumber++; $newNumber++
        }
        elseif ($newIndex -lt $newLines.Count -and ($oldIndex -ge $oldLines.Count -or $matrix[$oldIndex, ($newIndex + 1)] -gt $matrix[($oldIndex + 1), $newIndex])) {
            $records.Add([pscustomobject]@{ Kind = '+'; Old = $null; New = $newNumber; Text = $newLines[$newIndex] })
            $newIndex++; $newNumber++
        }
        else {
            $records.Add([pscustomobject]@{ Kind = '-'; Old = $oldNumber; New = $null; Text = $oldLines[$oldIndex] })
            $oldIndex++; $oldNumber++
        }
    }

    $keep = [System.Collections.Generic.HashSet[int]]::new()
    $changes = @(for ($index = 0; $index -lt $records.Count; $index++) { if ($records[$index].Kind -ne ' ') { $index } })
    if ($changes.Count -eq 0) {
        for ($index = 0; $index -lt $records.Count; $index++) { [void]$keep.Add($index) }
    }
    else {
        foreach ($change in $changes) {
            for ($index = [Math]::Max(0, $change - $ContextLines); $index -le [Math]::Min($records.Count - 1, $change + $ContextLines); $index++) {
                [void]$keep.Add($index)
            }
        }
    }

    $oldWidth = ([string][Math]::Max(1, $oldLines.Count)).Length
    $newWidth = ([string][Math]::Max(1, $newLines.Count)).Length
    $omitted = $false
    for ($index = 0; $index -lt $records.Count; $index++) {
        if (-not $keep.Contains($index)) {
            if (-not $omitted) { ConvertTo-PoshUITextRender '...'; $omitted = $true }
            continue
        }
        $omitted = $false
        $record = $records[$index]
        $wrapped = @(Split-PoshUITextWidth -Text $record.Text -Width $Width)
        for ($partIndex = 0; $partIndex -lt $wrapped.Count; $partIndex++) {
            if ($NoLineNumbers) { ConvertTo-PoshUITextRender "$($record.Kind) $($wrapped[$partIndex])"; continue }
            $oldLabel = if ($partIndex -eq 0 -and $null -ne $record.Old) { [string]$record.Old } else { '' }
            $newLabel = if ($partIndex -eq 0 -and $null -ne $record.New) { [string]$record.New } else { '' }
            ConvertTo-PoshUITextRender "$($record.Kind) $($oldLabel.PadLeft($oldWidth)) $($newLabel.PadLeft($newWidth)) | $($wrapped[$partIndex])"
        }
    }
}

function Show-PoshUIDiff {
    <#
    .SYNOPSIS
    Displays a line-oriented text diff
    .DESCRIPTION
    Formats old and new text with Format-PoshUIDiff and writes each line through
    the shared PoshUI host boundary.
    .PARAMETER OldText
    Original text or lines.
    .PARAMETER NewText
    Replacement text or lines.
    .PARAMETER ContextLines
    Unchanged lines retained around changes.
    .PARAMETER Width
    Maximum content width. Zero disables wrapping.
    .PARAMETER NoLineNumbers
    Omits line-number gutters.
    .INPUTS
    None
    .OUTPUTS
    None
    .EXAMPLE
    Show-PoshUIDiff -OldText $before -NewText $after

    Displays a numbered diff.
    .EXAMPLE
    Show-PoshUIDiff -OldText $before -NewText $after -ContextLines 0

    Displays changed lines only.
    .EXAMPLE
    Show-PoshUIDiff -OldText $before -NewText $after -Width 80 -NoLineNumbers

    Displays a wrapped marker-only diff.
    .NOTES
    Off mode suppresses host output through Write-PoshUIHost.
    .LINK
    Format-PoshUIDiff
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OldText,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NewText,
        [ValidateRange(0, [int]::MaxValue)][int]$ContextLines = 3,
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [switch]$NoLineNumbers
    )
    foreach ($line in @(Format-PoshUIDiff @PSBoundParameters)) { Write-PoshUIHost $line }
}

Export-ModuleMember -Function @(
    'Format-PoshUICodeBlock', 'Show-PoshUICodeBlock', 'Format-PoshUIDiff', 'Show-PoshUIDiff'
)
