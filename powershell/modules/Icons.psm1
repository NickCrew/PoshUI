#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script
$script:PoshUIStyle = Get-PoshUIStyleInternal

function Format-PoshUIHeader {
    <#
    .SYNOPSIS
        Formats an application header as composable lines.
    .DESCRIPTION
        Returns a labeled header without writing to the host.
    .PARAMETER Label
        Short label placed before the title.
    .PARAMETER Title
        Header title text.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Format-PoshUIHeader -Label RELEASE -Title 'Open releases'
    .EXAMPLE
        $lines = Format-PoshUIHeader -Label BUILD -Title 'Pipeline status'
    .EXAMPLE
        Format-PoshUIHeader TEST Results | Set-Content header.txt
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$Title
    )

    $text = ConvertTo-PoshUISafeRichText "$Label $Title"
    '', "$($script:PoshUIStyle.Bold)$text$($script:PoshUIStyle.Reset)", '' | ForEach-Object {
        if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $_ } else { ConvertTo-PoshUIPlainText $_ }
    }
}

function Show-PoshUIHeader {
    <#
    .SYNOPSIS
        Displays an application header through the PoshUI runtime.
    .DESCRIPTION
        Formats a labeled header and writes it through the runtime boundary.
    .PARAMETER Label
        Short label placed before the title.
    .PARAMETER Title
        Header title text.
    .OUTPUTS
        None.
    .EXAMPLE
        Show-PoshUIHeader -Label RELEASE -Title 'Open releases'
    .EXAMPLE
        Show-PoshUIHeader BUILD 'Pipeline status'
    .EXAMPLE
        Show-PoshUIHeader -Label TEST -Title Results
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$Title
    )

    Format-PoshUIHeader @PSBoundParameters | ForEach-Object { Write-PoshUIHost $_ }
}

function Format-PoshUISubheader {
    <#
    .SYNOPSIS
        Formats a composable application subheader.
    .DESCRIPTION
        Returns one pointer-prefixed title line without host output.
    .PARAMETER Title
        Subheader title text.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Format-PoshUISubheader -Title Summary
    .EXAMPLE
        $line = Format-PoshUISubheader 'Security reports'
    .EXAMPLE
        Format-PoshUISubheader Detail | Set-Content subheader.txt
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Title)

    $safeTitle = ConvertTo-PoshUISafeRichText $Title
    $line = "$($script:PoshUIStyle.Cyan)$($script:PoshUIStyle.Icon.Pointer)$($script:PoshUIStyle.Reset) $($script:PoshUIStyle.Bold)$safeTitle$($script:PoshUIStyle.Reset)"
    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
}

function Show-PoshUISubheader {
    <#
    .SYNOPSIS
        Displays an application subheader through the PoshUI runtime.
    .DESCRIPTION
        Formats a subheader and writes it through the runtime boundary.
    .PARAMETER Title
        Subheader title text.
    .OUTPUTS
        None.
    .EXAMPLE
        Show-PoshUISubheader -Title Summary
    .EXAMPLE
        Show-PoshUISubheader 'Security reports'
    .EXAMPLE
        Show-PoshUISubheader Detail
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param([Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Title)

    Write-PoshUIHost (Format-PoshUISubheader @PSBoundParameters)
}

function Format-PoshUIStatus {
    <#
    .SYNOPSIS
        Formats inline semantic status text.
    .DESCRIPTION
        Returns status text with a semantic icon and optional rich styling.
    .PARAMETER Kind
        Semantic status kind.
    .PARAMETER Text
        Status message placed after the icon.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Format-PoshUIStatus -Kind Success -Text Ready
    .EXAMPLE
        $status = Format-PoshUIStatus Warning 'Waiting for approval'
    .EXAMPLE
        Format-PoshUIStatus Error Failed | Set-Content status.txt
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Success', 'Error', 'Warning', 'Info')][string]$Kind,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$Text
    )

    $safeText = ConvertTo-PoshUISafeRichText $Text
    $line = switch ($Kind) {
        'Success' { "$($script:PoshUIStyle.Green)$($script:PoshUIStyle.Icon.Success)$($script:PoshUIStyle.Reset) $safeText" }
        'Error' { "$($script:PoshUIStyle.Red)$($script:PoshUIStyle.Icon.Error)$($script:PoshUIStyle.Reset) $safeText" }
        'Warning' { "$($script:PoshUIStyle.Yellow)$($script:PoshUIStyle.Icon.Warning)$($script:PoshUIStyle.Reset) $safeText" }
        'Info' { "$($script:PoshUIStyle.Blue)$($script:PoshUIStyle.Icon.Info)$($script:PoshUIStyle.Reset) $safeText" }
    }
    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
}

Export-ModuleMember -Function @(
    'Format-PoshUIHeader'
    'Show-PoshUIHeader'
    'Format-PoshUISubheader'
    'Show-PoshUISubheader'
    'Format-PoshUIStatus'
)
