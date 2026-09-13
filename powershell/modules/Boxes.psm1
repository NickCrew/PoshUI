#Requires -Version 7.6
# Native composable box rendering for PoshUI.

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script
$script:PoshUIStyle = Get-PoshUIStyleInternal
$script:PoshUIBoxDefaultWidth = 80

# ============================================================================
# Core Box Drawing Functions
# ============================================================================

function Format-PoshUIBox {
    <#
    .SYNOPSIS
    Formats a terminal box as composable text lines.

    .DESCRIPTION
    Creates a standard, rounded, or double-line box without writing to the
    host or changing terminal state. In plain runtime mode, ANSI control
    sequences are removed from the returned strings.

    .PARAMETER Title
    The optional title centered in the box header.

    .PARAMETER Content
    The content lines to place inside the box. Content can be supplied from
    the pipeline.

    .PARAMETER Color
    An optional ANSI color sequence applied to the box borders.

    .PARAMETER Width
    The total display width of the box, including its borders.

    .PARAMETER Style
    The border style: Standard, Rounded, or Double.

    .EXAMPLE
    Format-PoshUIBox -Title 'Status' -Content 'Ready' -Width 24

    Returns each rendered box row as a separate string.

    .EXAMPLE
    'One', 'Two' | Format-PoshUIBox -Title 'Items' -Style Rounded

    Collects pipeline input and returns one rounded box.

    .EXAMPLE
    Format-PoshUIBox -Content 'Warning' -Style Double | Set-Content box.txt

    Saves a double-line box without writing directly to the host.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Position = 1, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Content = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]$Color = $script:PoshUIStyle.BoxBorder,

        [Parameter()]
        [ValidateRange(3, [int]::MaxValue)]
        [int]$Width = $script:PoshUIBoxDefaultWidth,

        [Parameter()]
        [ValidateSet('Standard', 'Rounded', 'Double')]
        [string]$Style = 'Standard'
    )

    begin {
        $contentLines = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($line in $Content) {
            $contentLines.Add($line)
        }
    }

    end {
        $characters = switch ($Style) {
            'Rounded' { @{ TopLeft = '╭'; Horizontal = '─'; TopRight = '╮'; Vertical = '│'; LeftTee = '├'; RightTee = '┤'; BottomLeft = '╰'; BottomRight = '╯' } }
            default { @{ TopLeft = '╔'; Horizontal = '═'; TopRight = '╗'; Vertical = '║'; LeftTee = '╠'; RightTee = '╣'; BottomLeft = '╚'; BottomRight = '╝' } }
        }

        $rendered = [System.Collections.Generic.List[string]]::new()
        $rendered.Add("$Color$($characters.TopLeft)$($characters.Horizontal * [Math]::Max(0, $Width - 2))$($characters.TopRight)$($script:PoshUIStyle.Reset)")

        if ($Title) {
            $titleLine = @(Format-PoshUIText -InputObject "$($script:PoshUIStyle.BoxTitle)$Title$($script:PoshUIStyle.Reset)" `
                    -Width ($Width - 2) -HorizontalAlignment Center -Overflow Truncate)[0]
            $rendered.Add("$Color$($characters.Vertical)$($script:PoshUIStyle.Reset)$titleLine$Color$($characters.Vertical)$($script:PoshUIStyle.Reset)")
            $rendered.Add("$Color$($characters.LeftTee)$($characters.Horizontal * [Math]::Max(0, $Width - 2))$($characters.RightTee)$($script:PoshUIStyle.Reset)")
        }

        foreach ($line in $contentLines) {
            $contentLine = @(Format-PoshUIText -InputObject $line -Width ($Width - 3) -Overflow Truncate)[0]
            $rendered.Add("$Color$($characters.Vertical)$($script:PoshUIStyle.Reset) $contentLine$Color$($characters.Vertical)$($script:PoshUIStyle.Reset)")
        }

        $rendered.Add("$Color$($characters.BottomLeft)$($characters.Horizontal * [Math]::Max(0, $Width - 2))$($characters.BottomRight)$($script:PoshUIStyle.Reset)")

        foreach ($line in $rendered) {
            if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
        }
    }
}

function Show-PoshUIBox {
    <#
    .SYNOPSIS
    Displays a terminal box through the PoshUI runtime boundary.

    .DESCRIPTION
    Formats a box with Format-PoshUIBox and writes each line through
    Write-PoshUIHost. Runtime modes therefore control color, redirection, and
    disabled output consistently with the rest of PoshUI.

    .PARAMETER Title
    The optional title centered in the box header.

    .PARAMETER Content
    The content lines to display. Content can be supplied from the pipeline.

    .PARAMETER Color
    An optional ANSI color sequence applied to the box borders.

    .PARAMETER Width
    The total display width of the box, including its borders.

    .PARAMETER Style
    The border style: Standard, Rounded, or Double.

    .EXAMPLE
    Show-PoshUIBox -Title 'Status' -Content 'Ready' -Width 24

    Displays a standard box through the configured runtime.

    .EXAMPLE
    'One', 'Two' | Show-PoshUIBox -Title 'Items' -Style Rounded

    Collects pipeline input and displays one rounded box.

    .EXAMPLE
    Show-PoshUIBox -Content 'Warning' -Style Double

    Displays a double-line box through the configured runtime.

    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Position = 1, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Content = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]$Color = $script:PoshUIStyle.BoxBorder,

        [Parameter()]
        [ValidateRange(3, [int]::MaxValue)]
        [int]$Width = $script:PoshUIBoxDefaultWidth,

        [Parameter()]
        [ValidateSet('Standard', 'Rounded', 'Double')]
        [string]$Style = 'Standard'
    )

    begin {
        $contentLines = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($line in $Content) {
            $contentLines.Add($line)
        }
    }

    end {
        Format-PoshUIBox -Title $Title -Content $contentLines.ToArray() -Color $Color -Width $Width -Style $Style |
            ForEach-Object { Write-PoshUIHost $_ }
    }
}
Export-ModuleMember -Function @(
    'Format-PoshUIBox'
    'Show-PoshUIBox'
)
