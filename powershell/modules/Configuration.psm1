#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop

function New-PoshUIThemeInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory theme value and does not mutate external state.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $primitive = [ordered]@{
        Black   = "`e[0;30m"
        Red     = "`e[0;31m"
        Green   = "`e[0;32m"
        Yellow  = "`e[0;33m"
        Blue    = "`e[0;34m"
        Magenta = "`e[0;35m"
        Cyan    = "`e[0;36m"
        White   = "`e[0;37m"
        Bold    = "`e[1m"
        Dim     = "`e[2m"
        Reverse = "`e[7m"
        Reset   = "`e[0m"
    }

    $semantic = switch ($Name) {
        'light' {
            [ordered]@{
                Background = $primitive.White
                Foreground = $primitive.Black
                Primary    = $primitive.Blue
                Accent     = $primitive.Magenta
                Success    = $primitive.Green
                Warning    = $primitive.Yellow
                Danger     = $primitive.Red
                Muted      = $primitive.Dim
            }
        }
        { $_ -in 'unanet', 'unafy' } {
            [ordered]@{
                Background = "`e[48;2;16;54;90m"
                Foreground = "`e[38;2;252;252;253m"
                Primary    = "`e[38;2;0;171;254m"
                Accent     = "`e[38;2;173;232;58m"
                Success    = $primitive.Green
                Warning    = $primitive.Yellow
                Danger     = $primitive.Red
                Muted      = $primitive.Dim
            }
        }
        default {
            [ordered]@{
                Background = $primitive.Black
                Foreground = $primitive.White
                Primary    = $primitive.Blue
                Accent     = $primitive.Cyan
                Success    = $primitive.Green
                Warning    = $primitive.Yellow
                Danger     = $primitive.Red
                Muted      = $primitive.Dim
            }
        }
    }

    $component = [ordered]@{
        Box = [ordered]@{
            Border = $semantic.Primary
            Title  = $primitive.Bold + $semantic.Primary
        }
        Table = [ordered]@{
            Border = $semantic.Primary
            Header = $primitive.Bold + $semantic.Accent
        }
        Prompt = [ordered]@{
            Accent = $semantic.Accent
            Success = $semantic.Success
            Error = $semantic.Danger
        }
        Progress = [ordered]@{
            Complete = $semantic.Success
            Active   = $semantic.Accent
        }
        Chart = [ordered]@{
            Bar   = $semantic.Primary
            Empty = $semantic.Muted
        }
    }

    [pscustomobject]@{
        PSTypeName = 'PoshUI.Theme'
        Name       = $Name
        Primitive  = $primitive
        Semantic   = $semantic
        Component  = $component
    }
}

function New-PoshUITheme {
    <#
    .SYNOPSIS
        Creates an independent layered PoshUI theme

    .DESCRIPTION
        Creates primitive, semantic, and component token maps for one of the
        built-in themes. The returned object is independent of the active
        configuration and can be changed by a caller without mutating another
        theme or the process environment.

    .PARAMETER Name
        Built-in theme name. The default is unanet.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        PS> New-PoshUITheme

        Creates the dark theme.

    .EXAMPLE
        PS> $theme = New-PoshUITheme -Name unanet

        Creates an independent Unanet theme.

    .EXAMPLE
        PS> (New-PoshUITheme -Name light).Component.Table.Header

        Returns the light theme's table-header token.

    .NOTES
        Theme tokens are mode-neutral ANSI values. Formatting and display
        commands apply the active runtime mode when producing output.

    .LINK
        Get-PoshUIConfiguration
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('unanet', 'dark', 'light', 'unafy')]
        [string]$Name = 'unanet'
    )

    New-PoshUIThemeInternal -Name $Name
}

$script:PoshUIConfiguration = [pscustomobject]@{
    PSTypeName = 'PoshUI.Configuration'
    Theme      = New-PoshUIThemeInternal -Name 'unanet'
    Progress   = [pscustomobject]@{
        BarCharacter   = [string][char]0x2588
        EmptyCharacter = [string][char]0x2591
        Width          = 50
    }
    Table      = [pscustomobject]@{
        Style     = 'standard'
        Alignment = 'left'
        Padding   = 1
    }
    Logging    = [pscustomobject]@{
        Level        = 'INFO'
        File         = ''
        ToFile       = 'false'
        ToConsole    = 'true'
        MaximumSize  = 10485760L
        MaximumFiles = 5
    }
}

Set-PoshUIStyleInternal -Theme $script:PoshUIConfiguration.Theme

function Copy-PoshUIThemeInternal {
    param([Parameter(Mandatory)][PSTypeName('PoshUI.Theme')][psobject]$Theme)

    $copy = $Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json -Depth 8 -AsHashtable
    [pscustomobject]@{
        PSTypeName = 'PoshUI.Theme'
        Name = [string]$copy.Name
        Primitive = $copy.Primitive
        Semantic = $copy.Semantic
        Component = $copy.Component
    }
}

function Assert-PoshUIThemeInternal {
    param([Parameter(Mandatory)][PSTypeName('PoshUI.Theme')][psobject]$Theme)

    foreach ($path in @(
            'Primitive.Reset', 'Primitive.Bold', 'Primitive.Dim',
            'Semantic.Primary', 'Semantic.Accent', 'Semantic.Success', 'Semantic.Warning', 'Semantic.Danger',
            'Component.Box.Border', 'Component.Box.Title',
            'Component.Table.Border', 'Component.Table.Header',
            'Component.Prompt.Accent', 'Component.Progress.Active',
            'Component.Chart.Bar', 'Component.Chart.Empty'
        )) {
        $value = $Theme
        foreach ($segment in $path.Split('.')) { $value = $value.$segment }
        if ($null -eq $value) { throw [ArgumentException]::new("Theme is missing required token '$path'.") }
    }
}

function Set-PoshUITheme {
    <#
    .SYNOPSIS
        Sets the active PoshUI theme
    .DESCRIPTION
        Activates a built-in or caller-supplied theme for subsequent rich-mode
        rendering. PoshUI copies custom themes before activation, so later
        caller mutations cannot change module behavior. Plain and off modes
        continue to remove all theme control sequences.
    .PARAMETER Name
        Built-in theme name. The default is unanet.
    .PARAMETER Theme
        Custom PoshUI.Theme created by New-PoshUITheme and modified by the caller.
    .PARAMETER PassThru
        Returns an independent copy of the active theme.
    .INPUTS
        PoshUI.Theme.
    .OUTPUTS
        PoshUI.Theme when PassThru is supplied. Otherwise none.
    .EXAMPLE
        Set-PoshUITheme

        Activates the default Unanet theme.
    .EXAMPLE
        Set-PoshUITheme -Name dark -PassThru

        Activates and returns a copy of the dark theme.
    .EXAMPLE
        $theme = New-PoshUITheme -Name unanet
        $theme.Component.Box.Border = "`e[38;2;82;214;255m"
        $theme | Set-PoshUITheme

        Activates a customized independent theme.
    .NOTES
        Theme state is local to the imported PoshUI module instance and is not
        written to the process environment.
    .LINK
        New-PoshUITheme
    .LINK
        Get-PoshUIConfiguration
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name', SupportsShouldProcess)]
    [OutputType('PoshUI.Theme')]
    param(
        [Parameter(ParameterSetName = 'Name', Position = 0)]
        [ValidateSet('unanet', 'dark', 'light', 'unafy')]
        [string]$Name = 'unanet',

        [Parameter(Mandatory, ParameterSetName = 'Theme', ValueFromPipeline)]
        [PSTypeName('PoshUI.Theme')][psobject]$Theme,

        [switch]$PassThru
    )

    process {
        $nextTheme = if ($PSCmdlet.ParameterSetName -eq 'Theme') {
            Assert-PoshUIThemeInternal -Theme $Theme
            Copy-PoshUIThemeInternal -Theme $Theme
        }
        else {
            New-PoshUIThemeInternal -Name $Name
        }

        if ($PSCmdlet.ShouldProcess('PoshUI active theme', "Set to '$($nextTheme.Name)'")) {
            $script:PoshUIConfiguration.Theme = $nextTheme
            Set-PoshUIStyleInternal -Theme $script:PoshUIConfiguration.Theme
        }
        if ($PassThru) { Copy-PoshUIThemeInternal -Theme $script:PoshUIConfiguration.Theme }
    }
}

function Get-PoshUIConfiguration {
    <#
    .SYNOPSIS
        Gets the resolved PoshUI startup configuration

    .DESCRIPTION
        Returns an independent snapshot of the active module-owned settings.
        Runtime mode and feature toggles remain explicit process inputs, while
        theme and component settings stay in module scope.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        PS> Get-PoshUIConfiguration

        Returns every resolved configuration section.

    .EXAMPLE
        PS> (Get-PoshUIConfiguration).Progress.Width

        Returns the resolved progress width.

    .EXAMPLE
        PS> (Get-PoshUIConfiguration).Theme.Component.Table

        Returns the active table component tokens.

    .NOTES
        POSH_UI_MODE remains a process-level runtime switch and is resolved by
        Get-PoshUIRuntime rather than this startup snapshot.

    .LINK
        New-PoshUITheme

    .LINK
        Get-PoshUIRuntime
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $script:PoshUIConfiguration | ConvertTo-Json -Depth 8 | ConvertFrom-Json -Depth 8
}

Export-ModuleMember -Function @(
    'Get-PoshUIConfiguration'
    'New-PoshUITheme'
    'Set-PoshUITheme'
)
