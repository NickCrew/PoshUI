#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop

function Write-PoshUISearchCursorVisibilityInternal {
    param(
        [Parameter(Mandatory)][bool]$Visible,
        [Parameter(Mandatory)][object]$OwnerId,
        [switch]$Force
    )

    $sequence = if ($Visible) { "`e[?25h" } else { "`e[?25l" }
    if ($Force) {
        [Console]::Out.Write($sequence)
        return
    }
    Write-PoshUIHost -Object $sequence -NoNewline -OwnerId $OwnerId -TrustedControl
}

function Get-PoshUIFirstEnabledIndexInternal {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)

    for ($index = 0; $index -lt $Items.Count; $index++) {
        if ($Items[$index].Enabled) { return $index }
    }
    -1
}

function Move-PoshUISelectionInternal {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][int]$CurrentIndex,
        [Parameter(Mandatory)][ValidateSet(-1, 1)][int]$Direction
    )

    if ($Items.Count -eq 0) { return -1 }
    $enabledCount = @($Items | Where-Object Enabled).Count
    if ($enabledCount -eq 0) { return -1 }

    $candidate = $CurrentIndex
    for ($attempt = 0; $attempt -lt $Items.Count; $attempt++) {
        $candidate = ($candidate + $Direction + $Items.Count) % $Items.Count
        if ($Items[$candidate].Enabled) { return $candidate }
    }
    -1
}

function Read-PoshUISearchKeyInternal {
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
        ([ConsoleKey]::UpArrow) { return [pscustomobject]@{ Action = 'Previous'; Character = '' } }
        ([ConsoleKey]::DownArrow) { return [pscustomobject]@{ Action = 'Next'; Character = '' } }
        ([ConsoleKey]::Backspace) { return [pscustomobject]@{ Action = 'Backspace'; Character = '' } }
        ([ConsoleKey]::Escape) { return [pscustomobject]@{ Action = 'Cancel'; Character = '' } }
        ([ConsoleKey]::Enter) { return [pscustomobject]@{ Action = 'Accept'; Character = '' } }
        default {
            if (-not [char]::IsControl($key.KeyChar)) {
                return [pscustomobject]@{ Action = 'Append'; Character = [string]$key.KeyChar }
            }
            return [pscustomobject]@{ Action = 'None'; Character = '' }
        }
    }
}

function Write-PoshUISearchFrameInternal {
    param(
        [Parameter(Mandatory)][PSTypeName('PoshUI.SearchSelection')][psobject]$Selection,
        [Parameter(Mandatory)][int]$PreviousLineCount,
        [Parameter(Mandatory)][object]$OwnerId
    )

    $terminalWidth = try { [Console]::WindowWidth } catch { 80 }
    $width = if ($terminalWidth -gt 1) { $terminalWidth - 1 } else { 80 }
    $lines = [string[]]@(Format-PoshUISearchSelection -Selection $Selection -Width $width -Overflow Wrap)
    $messages = [string[]]@(Get-PoshUIDeferredOutput -OwnerId $OwnerId)
    if ($PreviousLineCount -gt 0) {
        Write-PoshUIHost -Object ("`e[{0}A" -f $PreviousLineCount) -NoNewline -OwnerId $OwnerId -TrustedControl
    }
    foreach ($message in $messages) {
        Write-PoshUIHost -Object "`e[2K$(ConvertTo-PoshUISafeRichText $message)" -OwnerId $OwnerId -TrustedControl
    }
    $lineCount = [Math]::Max($PreviousLineCount, $lines.Count)
    for ($index = 0; $index -lt $lineCount; $index++) {
        $line = if ($index -lt $lines.Count) { $lines[$index] } else { '' }
        Write-PoshUIHost -Object "`e[2K$line" -OwnerId $OwnerId -TrustedControl
    }
    if ($lineCount -gt $lines.Count) {
        Write-PoshUIHost -Object ("`e[{0}A" -f ($lineCount - $lines.Count)) -NoNewline -OwnerId $OwnerId -TrustedControl
    }
    Complete-PoshUIDeferredOutput -OwnerId $OwnerId -Count $messages.Count
    $lines.Count
}

function ConvertTo-PoshUISearchTextInternal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $Text } else { ConvertTo-PoshUIPlainText $Text }
}

function Resize-PoshUISearchTextInternal {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Width,
        [Parameter(Mandatory)][ValidateSet('Truncate', 'Wrap')][string]$Overflow
    )

    foreach ($line in @(Format-PoshUIText -InputObject $Text -Width $Width -Overflow $Overflow)) {
        $line.TrimEnd()
    }
}

function New-PoshUISelectionItem {
    <#
    .SYNOPSIS
    Creates a typed searchable-selection item.
    .DESCRIPTION
    Associates a display label with an arbitrary typed value, optional preview
    text, search keywords, and enabled state. The value is retained without
    string conversion.
    .PARAMETER Label
    Text displayed and searched for the item.
    .PARAMETER Value
    The value returned when this item is accepted.
    .PARAMETER Preview
    Optional detail displayed while the item is selected.
    .PARAMETER Keywords
    Additional terms considered by filtering.
    .PARAMETER Disabled
    Prevents navigation to and acceptance of the item.
    .EXAMPLE
    New-PoshUISelectionItem -Label Production -Value 3
    .EXAMPLE
    New-PoshUISelectionItem QA ([uri]'https://qa.example.test') -Preview 'Quality assurance'
    .EXAMPLE
    New-PoshUISelectionItem Legacy old -Keywords archive,retired -Disabled
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Label,

        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [object]$Value,

        [AllowEmptyString()]
        [string]$Preview = '',

        [AllowEmptyCollection()]
        [string[]]$Keywords = @(),

        [switch]$Disabled
    )

    $item = [pscustomobject]@{
        Label    = $Label
        Value    = $Value
        Preview  = $Preview
        Keywords = [string[]]@($Keywords)
        Enabled  = -not $Disabled
    }
    $item.PSObject.TypeNames.Insert(0, 'PoshUI.SelectionItem')
    $item
}

function Find-PoshUISelectionItem {
    <#
    .SYNOPSIS
    Filters selection items by an incremental query.
    .DESCRIPTION
    Returns items whose label or keywords contain every whitespace-separated
    query token. Matching is case-insensitive and preserves source order and
    disabled items.
    .PARAMETER Item
    Typed items to filter.
    .PARAMETER Query
    The incremental search text. Empty text returns every item.
    .EXAMPLE
    Find-PoshUISelectionItem -Item $items -Query prod
    .EXAMPLE
    $items | Find-PoshUISelectionItem -Query 'east api'
    .EXAMPLE
    Find-PoshUISelectionItem $items ''
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.SelectionItem')]
        [psobject[]]$Item,

        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string]$Query = ''
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($candidate in $Item) { $collected.Add($candidate) }
    }
    end {
        $tokens = @($Query.Trim() -split '\s+' | Where-Object { $_ })
        foreach ($candidate in $collected) {
            $searchText = (@($candidate.Label) + @($candidate.Keywords)) -join ' '
            $candidateMatches = $true
            foreach ($token in $tokens) {
                if ($searchText.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    $candidateMatches = $false
                    break
                }
            }
            if ($candidateMatches) { $candidate }
        }
    }
}

function New-PoshUISearchSelection {
    <#
    .SYNOPSIS
    Creates an independent searchable-selection model.
    .DESCRIPTION
    Creates a typed state model containing source items, filtered items, query,
    navigation position, and acceptance or cancellation state. It performs no
    terminal input or output.
    .PARAMETER Item
    Items created by New-PoshUISelectionItem.
    .PARAMETER Prompt
    Text displayed above the query and choices.
    .EXAMPLE
    $selection = New-PoshUISearchSelection -Item $items
    .EXAMPLE
    $selection = $items | New-PoshUISearchSelection -Prompt 'Environment'
    .EXAMPLE
    New-PoshUISearchSelection $items 'Choose a target' | Format-PoshUISearchSelection
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.SelectionItem')]
        [ValidateNotNullOrEmpty()]
        [psobject[]]$Item,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt = 'Select an item'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($candidate in $Item) { $collected.Add($candidate) }
    }
    end {
        if ($collected.Count -eq 0) {
            throw [System.ArgumentException]::new('At least one selection item is required.')
        }
        $source = [object[]]@($collected)
        $selection = [pscustomobject]@{
            Prompt        = $Prompt
            Items         = $source
            Query         = ''
            FilteredItems = $source
            SelectedIndex = Get-PoshUIFirstEnabledIndexInternal -Items $source
            IsAccepted    = $false
            IsCancelled   = $false
            Result        = $null
        }
        $selection.PSObject.TypeNames.Insert(0, 'PoshUI.SearchSelection')
        $selection
    }
}

function Update-PoshUISearchSelection {
    <#
    .SYNOPSIS
    Applies one input action to a searchable-selection model.
    .DESCRIPTION
    Updates query, filtering, navigation, cancellation, or acceptance state.
    Navigation wraps and skips disabled entries. The supplied model is the only
    state mutated.
    .PARAMETER Selection
    The searchable-selection model to update.
    .PARAMETER Action
    The input action to apply.
    .PARAMETER Character
    A character appended when Action is Append.
    .PARAMETER PassThru
    Returns the updated selection.
    .EXAMPLE
    Update-PoshUISearchSelection $selection Next
    .EXAMPLE
    $selection | Update-PoshUISearchSelection -Action Append -Character p
    .EXAMPLE
    Update-PoshUISearchSelection $selection Accept -PassThru
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory selection model.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.SearchSelection')]
        [psobject]$Selection,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('Next', 'Previous', 'Append', 'Backspace', 'Reset', 'Accept', 'Cancel', 'None')]
        [string]$Action,

        [ValidateLength(0, 1)]
        [string]$Character = '',

        [switch]$PassThru
    )

    process {
        if ($Selection.IsAccepted -or $Selection.IsCancelled) {
            if ($PassThru) { $Selection }
            return
        }

        switch ($Action) {
            'Append' {
                if ([string]::IsNullOrEmpty($Character)) {
                    throw [System.ArgumentException]::new('Character is required for the Append action.')
                }
                $Selection.Query += $Character
            }
            'Backspace' {
                if ($Selection.Query.Length -gt 0) {
                    $Selection.Query = $Selection.Query.Substring(0, $Selection.Query.Length - 1)
                }
            }
            'Reset' { $Selection.Query = '' }
            'Cancel' {
                $Selection.IsCancelled = $true
                $Selection.Result = $null
            }
        }

        if ($Action -in 'Append', 'Backspace', 'Reset') {
            $Selection.FilteredItems = [object[]]@(
                Find-PoshUISelectionItem -Item $Selection.Items -Query $Selection.Query
            )
            $Selection.SelectedIndex = Get-PoshUIFirstEnabledIndexInternal -Items $Selection.FilteredItems
        }
        elseif ($Action -eq 'Next') {
            $Selection.SelectedIndex = Move-PoshUISelectionInternal -Items $Selection.FilteredItems `
                -CurrentIndex $Selection.SelectedIndex -Direction 1
        }
        elseif ($Action -eq 'Previous') {
            $Selection.SelectedIndex = Move-PoshUISelectionInternal -Items $Selection.FilteredItems `
                -CurrentIndex $Selection.SelectedIndex -Direction -1
        }
        elseif ($Action -eq 'Accept' -and $Selection.SelectedIndex -ge 0) {
            $candidate = $Selection.FilteredItems[$Selection.SelectedIndex]
            if ($candidate.Enabled) {
                $Selection.Result = $candidate.Value
                $Selection.IsAccepted = $true
            }
        }

        if ($PassThru) { $Selection }
    }
}

function Format-PoshUISearchSelection {
    <#
    .SYNOPSIS
    Formats a searchable selection without terminal effects.
    .DESCRIPTION
    Returns stable plain-text lines for the prompt, incremental query, filtered
    choices, empty state, and optional selected-item preview.
    .PARAMETER Selection
    The searchable-selection model to format.
    .PARAMETER NoPreview
    Suppresses optional preview text.
    .PARAMETER Width
    Maximum output width. Zero, the default, disables width limiting.
    .PARAMETER Overflow
    Truncates long lines with an ellipsis or wraps them at Width without
    splitting a grapheme cluster.
    .EXAMPLE
    Format-PoshUISearchSelection $selection
    .EXAMPLE
    $lines = $selection | Format-PoshUISearchSelection -NoPreview
    .EXAMPLE
    Format-PoshUISearchSelection $selection -Width 24 -Overflow Wrap
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.SearchSelection')]
        [psobject]$Selection,

        [switch]$NoPreview,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Width = 0,

        [ValidateSet('Truncate', 'Wrap')]
        [string]$Overflow = 'Truncate'
    )

    process {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add((ConvertTo-PoshUISearchTextInternal $Selection.Prompt))
        $lines.Add((ConvertTo-PoshUISearchTextInternal "Filter: $($Selection.Query)"))
        if ($Selection.FilteredItems.Count -eq 0) {
            $lines.Add('  No matches')
        }
        else {
            for ($index = 0; $index -lt $Selection.FilteredItems.Count; $index++) {
                $item = $Selection.FilteredItems[$index]
                $marker = if ($index -eq $Selection.SelectedIndex) { '>' } else { ' ' }
                $suffix = if ($item.Enabled) { '' } else { ' (disabled)' }
                $lines.Add((ConvertTo-PoshUISearchTextInternal "$marker $($item.Label)$suffix"))
            }
            if (-not $NoPreview -and $Selection.SelectedIndex -ge 0) {
                $selected = $Selection.FilteredItems[$Selection.SelectedIndex]
                if (-not [string]::IsNullOrEmpty($selected.Preview)) {
                    $lines.Add((ConvertTo-PoshUISearchTextInternal "Preview: $($selected.Preview)"))
                }
            }
        }

        foreach ($line in $lines) {
            if ($Width -gt 0) {
                Resize-PoshUISearchTextInternal -Text $line -Width $Width -Overflow $Overflow
            }
            else {
                $line
            }
        }
    }
}

function Select-PoshUIItem {
    <#
    .SYNOPSIS
    Interactively selects and returns one typed value.
    .DESCRIPTION
    Displays a searchable selection, reads incremental keyboard input, and
    returns the accepted item's original value. Redirected or unavailable input
    returns null immediately without reading from Console. Escape cancels.
    .PARAMETER Selection
    The searchable-selection model to run.
    .EXAMPLE
    $value = Select-PoshUIItem $selection
    .EXAMPLE
    $items | New-PoshUISearchSelection | Select-PoshUIItem
    .EXAMPLE
    if ($null -eq (Select-PoshUIItem $selection)) { 'Cancelled' }
    .OUTPUTS
    System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.SearchSelection')]
        [psobject]$Selection
    )

    process {
        $runtime = Get-PoshUIRuntime
        if ($runtime.Mode -eq 'off' -or -not $runtime.InteractiveInput) {
            return $null
        }

        $lineCount = 0
        $terminalControl = Test-PoshUITerminalControl
        $ownerId = [guid]::NewGuid()
        $leaseAcquired = $false
        try {
            if ($terminalControl) {
                Enter-PoshUICursorLease -OwnerId $ownerId
                $leaseAcquired = $true
                Write-PoshUISearchCursorVisibilityInternal -Visible $false -OwnerId $ownerId
            }
            while (-not $Selection.IsAccepted -and -not $Selection.IsCancelled) {
                if ($terminalControl) {
                    $lineCount = Write-PoshUISearchFrameInternal -Selection $Selection `
                        -PreviousLineCount $lineCount -OwnerId $ownerId
                }
                else {
                    Format-PoshUISearchSelection -Selection $Selection |
                        ForEach-Object { Write-PoshUIHost $_ }
                }
                $key = Read-PoshUISearchKeyInternal
                Update-PoshUISearchSelection -Selection $Selection -Action $key.Action -Character $key.Character
            }
            if ($Selection.IsAccepted) { return $Selection.Result }
            return $null
        }
        finally {
            if ($leaseAcquired) {
                try {
                    Write-PoshUISearchCursorVisibilityInternal -Visible $true -OwnerId $ownerId -Force
                }
                finally {
                    Exit-PoshUICursorLease -OwnerId $ownerId
                }
            }
        }
    }
}

Export-ModuleMember -Function @(
    'New-PoshUISelectionItem'
    'Find-PoshUISelectionItem'
    'New-PoshUISearchSelection'
    'Update-PoshUISearchSelection'
    'Format-PoshUISearchSelection'
    'Select-PoshUIItem'
)
