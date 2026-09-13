#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop

function Test-PoshUITwoColumnCodePointInternal {
    param([Parameter(Mandatory)][int]$CodePoint)

    $ranges = @(
        0x1100, 0x115F
        0x2329, 0x232A
        0x2E80, 0x303E
        0x3041, 0x33FF
        0x3400, 0x4DBF
        0x4E00, 0x9FFF
        0xA000, 0xA4CF
        0xAC00, 0xD7A3
        0xF900, 0xFAFF
        0xFE10, 0xFE19
        0xFE30, 0xFE6F
        0xFF00, 0xFF60
        0xFFE0, 0xFFE6
        0x1F300, 0x1F64F
        0x1F680, 0x1F6FF
        0x1F700, 0x1F77F
        0x1F780, 0x1F7FF
        0x1F800, 0x1F8FF
        0x1F900, 0x1F9FF
        0x1FA00, 0x1FAFF
        0x20000, 0x2FFFD
        0x30000, 0x3FFFD
        0x231A, 0x231B
        0x23E9, 0x23EC
        0x23F0, 0x23F0
        0x23F3, 0x23F3
        0x25FD, 0x25FE
        0x2614, 0x2615
        0x2648, 0x2653
        0x267F, 0x267F
        0x2693, 0x2693
        0x26A1, 0x26A1
        0x26AA, 0x26AB
        0x26BD, 0x26BE
        0x26C4, 0x26C5
        0x26CE, 0x26CE
        0x26D4, 0x26D4
        0x26EA, 0x26EA
        0x26F2, 0x26F3
        0x26F5, 0x26F5
        0x26FA, 0x26FA
        0x26FD, 0x26FD
        0x2705, 0x2705
        0x270A, 0x270B
        0x2728, 0x2728
        0x274C, 0x274C
        0x274E, 0x274E
        0x2753, 0x2755
        0x2757, 0x2757
        0x2795, 0x2797
        0x27B0, 0x27B0
        0x27BF, 0x27BF
        0x2B1B, 0x2B1C
        0x2B50, 0x2B50
        0x2B55, 0x2B55
    )

    for ($index = 0; $index -lt $ranges.Count; $index += 2) {
        if ($CodePoint -ge $ranges[$index] -and $CodePoint -le $ranges[$index + 1]) {
            return $true
        }
    }
    $false
}

function Measure-PoshUITextWidthInternal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $runes = @((ConvertTo-PoshUIPlainText $Text).EnumerateRunes())
    $width = 0
    for ($index = 0; $index -lt $runes.Count; $index++) {
        $codePoint = $runes[$index].Value
        if ($codePoint -eq 0x200D -or $codePoint -eq 0xFE0E -or $codePoint -eq 0xFE0F) {
            continue
        }

        $category = [Text.Rune]::GetUnicodeCategory($runes[$index])
        if ($category -in @(
                [Globalization.UnicodeCategory]::NonSpacingMark
                [Globalization.UnicodeCategory]::EnclosingMark
                [Globalization.UnicodeCategory]::Format
            )) {
            continue
        }

        if (($index + 1 -lt $runes.Count) -and $runes[$index + 1].Value -eq 0xFE0F) {
            $width += 2
        }
        elseif (Test-PoshUITwoColumnCodePointInternal -CodePoint $codePoint) {
            $width += 2
        }
        else {
            $width++
        }
    }
    $width
}

Export-ModuleMember -Function 'Measure-PoshUITextWidthInternal'
