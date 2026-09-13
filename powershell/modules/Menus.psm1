#Requires -Version 7.6
# Native menu models, formatting, display, and safe action invocation.

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Colors.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script

# ============================================================================
# PowerShell-native Menu API
# ============================================================================

function New-PoshUIMenu {
    <#
    .SYNOPSIS
    Creates an independent PoshUI menu model.
    .DESCRIPTION
    Returns a menu whose items and selection are isolated from every other menu instance.
    .PARAMETER Title
    Text displayed in the menu header.
    .EXAMPLE
    $menu = New-PoshUIMenu -Title 'Deploy'
    .EXAMPLE
    $main = New-PoshUIMenu 'Main'; $tools = New-PoshUIMenu 'Tools'
    .EXAMPLE
    New-PoshUIMenu -Title 'Actions' | Format-PoshUIMenu
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Title)

    $menu = [pscustomobject]@{ Title = $Title; Items = [object[]]@(); SelectedIndex = 0 }
    $menu.PSObject.TypeNames.Insert(0, 'PoshUI.Menu')
    $menu
}

function Add-PoshUIMenuItem {
    <#
    .SYNOPSIS
    Adds an item to an independent PoshUI menu.
    .DESCRIPTION
    Mutates only the supplied in-memory menu model and optionally returns it.
    .PARAMETER Menu
    Menu returned by New-PoshUIMenu.
    .PARAMETER Label
    Item text displayed to the user.
    .PARAMETER Action
    Optional action metadata retained with the item.
    .PARAMETER Hotkey
    Optional key label displayed before the item.
    .PARAMETER Disabled
    Marks the item unavailable.
    .PARAMETER PassThru
    Returns the updated menu.
    .EXAMPLE
    Add-PoshUIMenuItem -Menu $menu -Label 'Deploy' -Hotkey d
    .EXAMPLE
    $menu | Add-PoshUIMenuItem -Label 'Exit' -Action exit
    .EXAMPLE
    Add-PoshUIMenuItem $menu 'Unavailable' -Disabled -PassThru
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory menu model.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Menu')][psobject]$Menu,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$Label,
        [AllowNull()][object]$Action,
        [AllowEmptyString()][string]$Hotkey = '',
        [switch]$Disabled,
        [switch]$PassThru
    )
    process {
        $Menu.Items = [object[]]@($Menu.Items) + [pscustomobject]@{
            Label = $Label; Action = $Action; Hotkey = $Hotkey; Enabled = -not $Disabled
        }
        if ($PassThru) { $Menu }
    }
}

function Format-PoshUIMenu {
    <#
    .SYNOPSIS
    Formats an independent menu as composable text lines.
    .DESCRIPTION
    Returns a stable menu representation without host or cursor effects.
    .PARAMETER Menu
    Menu returned by New-PoshUIMenu.
    .PARAMETER SelectedIndex
    Zero-based item index to mark as selected.
    .EXAMPLE
    Format-PoshUIMenu -Menu $menu
    .EXAMPLE
    $lines = $menu | Format-PoshUIMenu -SelectedIndex 1
    .EXAMPLE
    Format-PoshUIMenu $menu | Set-Content menu.txt
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Menu')][psobject]$Menu,
        [ValidateRange(0, [int]::MaxValue)][int]$SelectedIndex = $Menu.SelectedIndex
    )
    process {
        $contentWidth = [Math]::Max((Measure-PoshUITextWidthInternal $Menu.Title), 1)
        foreach ($item in $Menu.Items) {
            $prefix = if ($item.Hotkey) { "[$($item.Hotkey)] " } else { '' }
            $disabled = if ($item.Enabled) { '' } else { ' (disabled)' }
            $contentWidth = [Math]::Max($contentWidth, (Measure-PoshUITextWidthInternal ($prefix + $item.Label + $disabled)))
        }
        $width = $contentWidth + 4
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("╔$('═' * $width)╗")
        $titlePadding = $width - (Measure-PoshUITextWidthInternal $Menu.Title)
        $lines.Add("║ $($Menu.Title)$(' ' * [Math]::Max(0, $titlePadding - 1))║")
        $lines.Add("╠$('═' * $width)╣")
        for ($i = 0; $i -lt $Menu.Items.Count; $i++) {
            $item = $Menu.Items[$i]
            $marker = if ($i -eq $SelectedIndex) { '>' } else { ' ' }
            $prefix = if ($item.Hotkey) { "[$($item.Hotkey)] " } else { '' }
            $disabled = if ($item.Enabled) { '' } else { ' (disabled)' }
            $content = "$marker $prefix$($item.Label)$disabled"
            $padding = $width - (Measure-PoshUITextWidthInternal $content)
            $lines.Add("║$content$(' ' * [Math]::Max(0, $padding))║")
        }
        $lines.Add("╚$('═' * $width)╝")
        foreach ($line in $lines) {
            if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
        }
    }
}

function Show-PoshUIMenu {
    <#
    .SYNOPSIS
    Displays an independent menu through the runtime boundary.
    .DESCRIPTION
    Formats the menu and writes each line without taking ownership of keyboard input.
    .PARAMETER Menu
    Menu returned by New-PoshUIMenu.
    .PARAMETER SelectedIndex
    Zero-based item index to mark as selected.
    .EXAMPLE
    Show-PoshUIMenu -Menu $menu
    .EXAMPLE
    $menu | Show-PoshUIMenu -SelectedIndex 1
    .EXAMPLE
    Show-PoshUIMenu $menu 0
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Menu')][psobject]$Menu,
        [Parameter(Position = 1)][ValidateRange(0, [int]::MaxValue)][int]$SelectedIndex = $Menu.SelectedIndex
    )
    process {
        Format-PoshUIMenu -Menu $Menu -SelectedIndex $SelectedIndex |
            ForEach-Object { Write-PoshUIHost $_ }
    }
}

function Invoke-PoshUIMenuAction {
    <#
    .SYNOPSIS
    Invokes one enabled menu item's action.
    .DESCRIPTION
    Invokes a script block, CommandInfo object, or exact command-name string
    without evaluating command text. The action's original typed output is
    returned. Disabled items and unsafe or unresolved command strings produce
    terminating errors.
    .PARAMETER Menu
    Menu returned by New-PoshUIMenu.
    .PARAMETER SelectedIndex
    Zero-based index of the item to invoke. Defaults to the model selection.
    .PARAMETER ArgumentList
    Optional positional arguments passed to the selected action.
    .EXAMPLE
    Invoke-PoshUIMenuAction -Menu $menu
    .EXAMPLE
    $result = $menu | Invoke-PoshUIMenuAction -SelectedIndex 1
    .EXAMPLE
    Invoke-PoshUIMenuAction $menu 0 -ArgumentList 'release'
    .OUTPUTS
    System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.Menu')]
        [psobject]$Menu,

        [Parameter(Position = 1)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$SelectedIndex = $Menu.SelectedIndex,

        [Parameter(Position = 2)]
        [AllowEmptyCollection()]
        [object[]]$ArgumentList = @()
    )

    process {
        if ($SelectedIndex -ge $Menu.Items.Count) {
            throw [System.ArgumentOutOfRangeException]::new(
                'SelectedIndex', $SelectedIndex, 'The selected menu item does not exist.')
        }

        $item = $Menu.Items[$SelectedIndex]
        if (-not $item.Enabled) {
            throw [System.InvalidOperationException]::new("Menu item '$($item.Label)' is disabled.")
        }
        if ($null -eq $item.Action) { return $null }

        if ($item.Action -is [scriptblock]) {
            return & $item.Action @ArgumentList
        }
        if ($item.Action -is [System.Management.Automation.CommandInfo]) {
            return & $item.Action @ArgumentList
        }
        if ($item.Action -is [string]) {
            $commandName = [string]$item.Action
            if ([string]::IsNullOrWhiteSpace($commandName) -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($commandName) -or
                $commandName -notmatch '^[\p{L}\p{N}_.:-]+$') {
                throw [System.ArgumentException]::new('String actions must be one exact command name.')
            }
            $command = Get-Command -Name $commandName -ErrorAction Stop
            return & $command @ArgumentList
        }

        throw [System.ArgumentException]::new(
            'Menu actions must be a script block, CommandInfo object, exact command name, or null.')
    }
}

Export-ModuleMember -Function @(
    'New-PoshUIMenu'
    'Add-PoshUIMenuItem'
    'Format-PoshUIMenu'
    'Show-PoshUIMenu'
    'Invoke-PoshUIMenuAction'
)
