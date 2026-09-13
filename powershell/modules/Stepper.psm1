#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop

function Measure-PoshUIStepperText {
    param([AllowEmptyString()][string]$Text)
    $width = 0
    $elements = [System.Globalization.StringInfo]::GetTextElementEnumerator((ConvertTo-PoshUIPlainText $Text))
    while ($elements.MoveNext()) {
        $elementWidth = 0
        $emoji = $false
        foreach ($rune in ([string]$elements.Current).EnumerateRunes()) {
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
            $elementWidth += $(if ($wide) { 2 } else { 1 })
        }
        $width += $(if ($emoji) { 2 } else { $elementWidth })
    }
    $width
}

function New-PoshUIStepper {
    <#
    .SYNOPSIS
    Creates an independent stepper or timeline model
    .DESCRIPTION
    Creates an in-memory model with its own mutable step collection. Multiple
    models can be updated and rendered independently. It owns no cursor state
    and performs no terminal writes.
    .PARAMETER Title
    Optional title rendered before the steps.
    .INPUTS
    None
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    New-PoshUIStepper

    Creates an untitled empty stepper.
    .EXAMPLE
    New-PoshUIStepper -Title Deployment

    Creates a titled deployment stepper.
    .EXAMPLE
    $timeline = New-PoshUIStepper -Title 'Release timeline'

    Stores an independent timeline model.
    .NOTES
    The returned Steps list belongs only to the new instance.
    .LINK
    Add-PoshUIStep
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory value without changing external state.')]
    param([AllowEmptyString()][string]$Title = '')

    [pscustomobject]@{
        PSTypeName = 'PoshUI.Stepper'
        Title      = $Title
        Steps      = [System.Collections.Generic.List[object]]::new()
    }
}

function Add-PoshUIStep {
    <#
    .SYNOPSIS
    Adds a stage to a stepper model
    .DESCRIPTION
    Adds one typed stage to the supplied independent model. Each stage has a
    stable identifier, visible status, optional description, typed value, and
    optional timestamp for timeline rendering.
    .PARAMETER Stepper
    PoshUI.Stepper model to mutate.
    .PARAMETER Id
    Unique step identifier within the model.
    .PARAMETER Label
    Human-readable stage label.
    .PARAMETER State
    Pending, Active, Success, Failed, or Skipped.
    .PARAMETER Description
    Optional expanded-style detail.
    .PARAMETER Value
    Optional typed consumer value retained on the stage.
    .PARAMETER Timestamp
    Optional point in time shown in the render model.
    .INPUTS
    None
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    Add-PoshUIStep -Stepper $steps -Id build -Label Build

    Adds a pending Build stage.
    .EXAMPLE
    Add-PoshUIStep -Stepper $steps -Id test -Label Test -State Active -Description 'Running Pester'

    Adds an active stage with detail.
    .EXAMPLE
    Add-PoshUIStep -Stepper $timeline -Id deploy -Label Deployed -State Success -Timestamp (Get-Date) -Value $release

    Adds a successful typed timeline event.
    .NOTES
    Duplicate identifiers are rejected.
    .LINK
    Set-PoshUIStep
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateScript({ $_.PSObject.TypeNames -contains 'PoshUI.Stepper' })][psobject]$Stepper,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Label,
        [ValidateSet('Pending', 'Active', 'Success', 'Failed', 'Skipped')][string]$State = 'Pending',
        [AllowEmptyString()][string]$Description = '',
        [AllowNull()][object]$Value,
        [Nullable[datetime]]$Timestamp
    )
    if ($Stepper.Steps.Id -contains $Id) { throw "A step with Id '$Id' already exists." }
    $Stepper.Steps.Add([pscustomobject]@{
        PSTypeName  = 'PoshUI.Step'
        Id          = $Id
        Label       = $Label
        State       = $State
        Description = $Description
        Value       = $Value
        Timestamp   = $Timestamp
    })
    $Stepper
}

function Set-PoshUIStep {
    <#
    .SYNOPSIS
    Updates a stage in a stepper model
    .DESCRIPTION
    Locates one stage by identifier and changes only explicitly supplied
    fields. The model remains independent of every other stepper instance.
    .PARAMETER Stepper
    PoshUI.Stepper model to mutate.
    .PARAMETER Id
    Identifier of the stage to update.
    .PARAMETER State
    Replacement stage state.
    .PARAMETER Label
    Replacement label.
    .PARAMETER Description
    Replacement expanded detail.
    .PARAMETER Value
    Replacement typed consumer value.
    .PARAMETER Timestamp
    Replacement timeline timestamp.
    .INPUTS
    None
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    Set-PoshUIStep -Stepper $steps -Id build -State Active

    Marks Build active.
    .EXAMPLE
    Set-PoshUIStep -Stepper $steps -Id build -State Success -Description 'Artifact ready'

    Completes Build and replaces its detail.
    .EXAMPLE
    Set-PoshUIStep -Stepper $timeline -Id deploy -Timestamp (Get-Date) -Value $result

    Records typed timeline completion data.
    .NOTES
    An unknown identifier is a terminating error.
    .LINK
    Format-PoshUIStepper
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Mutates only the caller-supplied in-memory model.')]
    param(
        [Parameter(Mandatory)][ValidateScript({ $_.PSObject.TypeNames -contains 'PoshUI.Stepper' })][psobject]$Stepper,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Id,
        [ValidateSet('Pending', 'Active', 'Success', 'Failed', 'Skipped')][string]$State,
        [ValidateNotNullOrEmpty()][string]$Label,
        [AllowEmptyString()][string]$Description,
        [AllowNull()][object]$Value,
        [Nullable[datetime]]$Timestamp
    )
    $step = $Stepper.Steps | Where-Object Id -CEQ $Id | Select-Object -First 1
    if ($null -eq $step) { throw "No step with Id '$Id' exists." }
    foreach ($name in 'State', 'Label', 'Description', 'Value', 'Timestamp') {
        if ($PSBoundParameters.ContainsKey($name)) { $step.$name = $PSBoundParameters[$name] }
    }
    $Stepper
}

function Format-PoshUIStepper {
    <#
    .SYNOPSIS
    Formats a stepper or timeline model as composable lines
    .DESCRIPTION
    Returns a deterministic render model with visible state words and optional
    timestamps. Icons supplement rather than replace state text. Compact style
    emits one line per step; Expanded style includes descriptions.
    .PARAMETER Stepper
    PoshUI.Stepper model to format.
    .PARAMETER Style
    Compact or Expanded presentation.
    .PARAMETER CharacterSet
    ASCII or Unicode icons and connectors.
    .PARAMETER TimestampFormat
    Date and time format applied to stages with timestamps.
    .PARAMETER Width
    Maximum terminal width. Zero uses the intrinsic width of the render model.
    .PARAMETER Overflow
    Wraps logical lines or truncates them with an ellipsis at Width.
    .INPUTS
    PoshUI.Stepper
    .OUTPUTS
    System.String
    .EXAMPLE
    Format-PoshUIStepper -Stepper $steps

    Returns a compact Unicode render model.
    .EXAMPLE
    $steps | Format-PoshUIStepper -Style Expanded

    Returns descriptions beneath stage lines.
    .EXAMPLE
    Format-PoshUIStepper -Stepper $timeline -CharacterSet ASCII -TimestampFormat 'HH:mm:ss' -Width 30 -Overflow Wrap

    Returns an ASCII timeline with time values.
    .NOTES
    The function is pure and does not mutate the supplied model.
    .LINK
    Show-PoshUIStepper
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][ValidateScript({ $_.PSObject.TypeNames -contains 'PoshUI.Stepper' })][psobject]$Stepper,
        [ValidateSet('Compact', 'Expanded')][string]$Style = 'Compact',
        [ValidateSet('ASCII', 'Unicode')][string]$CharacterSet = 'Unicode',
        [ValidateNotNullOrEmpty()][string]$TimestampFormat = 'yyyy-MM-dd HH:mm:ss',
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Wrap'
    )
    process {
        $logicalLines = [System.Collections.Generic.List[string]]::new()
        if ($Stepper.Title) { $logicalLines.Add([string]$Stepper.Title) }
        $icons = if ($CharacterSet -eq 'Unicode') {
            @{ Pending = '○'; Active = '◉'; Success = '✓'; Failed = '✗'; Skipped = '⊘' }
        }
        else { @{ Pending = 'o'; Active = '>'; Success = '+'; Failed = 'x'; Skipped = '-' } }
        $connector = if ($CharacterSet -eq 'Unicode') { '│' } else { '|' }
        for ($index = 0; $index -lt $Stepper.Steps.Count; $index++) {
            $step = $Stepper.Steps[$index]
            $timestamp = if ($null -ne $step.Timestamp) { ' ' + ([datetime]$step.Timestamp).ToString($TimestampFormat) } else { '' }
            $logicalLines.Add("$($icons[$step.State]) [$($step.State.ToUpperInvariant())]$timestamp $($step.Label)")
            if ($Style -eq 'Expanded' -and $step.Description) { $logicalLines.Add("  $connector $($step.Description)") }
            if ($index -lt $Stepper.Steps.Count - 1) { $logicalLines.Add($connector) }
        }
        if ($logicalLines.Count -eq 0) { return }
        $resolvedWidth = $Width
        if ($resolvedWidth -eq 0) {
            $resolvedWidth = [Math]::Max(1, [int](($logicalLines | ForEach-Object { Measure-PoshUIStepperText $_ } | Measure-Object -Maximum).Maximum))
        }
        foreach ($logicalLine in $logicalLines) {
            foreach ($line in @(Format-PoshUIText -InputObject $logicalLine -Width $resolvedWidth -Overflow $Overflow)) {
                $line.TrimEnd()
            }
        }
    }
}

function Show-PoshUIStepper {
    <#
    .SYNOPSIS
    Displays a stepper or timeline model
    .DESCRIPTION
    Formats a model with Format-PoshUIStepper and writes every line through the
    shared PoshUI host boundary. It does not claim or move the cursor.
    .PARAMETER Stepper
    PoshUI.Stepper model to display.
    .PARAMETER Style
    Compact or Expanded presentation.
    .PARAMETER CharacterSet
    ASCII or Unicode icons and connectors.
    .PARAMETER TimestampFormat
    Date and time format applied to stages with timestamps.
    .PARAMETER Width
    Maximum terminal width. Zero uses the intrinsic render width.
    .PARAMETER Overflow
    Wrap or Truncate behavior applied at Width.
    .INPUTS
    PoshUI.Stepper
    .OUTPUTS
    None
    .EXAMPLE
    Show-PoshUIStepper -Stepper $steps

    Displays a compact stepper.
    .EXAMPLE
    $steps | Show-PoshUIStepper -Style Expanded

    Displays stage descriptions.
    .EXAMPLE
    Show-PoshUIStepper -Stepper $timeline -CharacterSet ASCII -TimestampFormat 'HH:mm' -Width 40

    Displays an ASCII timeline.
    .NOTES
    Off mode suppresses host output through Write-PoshUIHost.
    .LINK
    Format-PoshUIStepper
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][ValidateScript({ $_.PSObject.TypeNames -contains 'PoshUI.Stepper' })][psobject]$Stepper,
        [ValidateSet('Compact', 'Expanded')][string]$Style = 'Compact',
        [ValidateSet('ASCII', 'Unicode')][string]$CharacterSet = 'Unicode',
        [ValidateNotNullOrEmpty()][string]$TimestampFormat = 'yyyy-MM-dd HH:mm:ss',
        [ValidateRange(0, [int]::MaxValue)][int]$Width = 0,
        [ValidateSet('Wrap', 'Truncate')][string]$Overflow = 'Wrap'
    )
    process { foreach ($line in @(Format-PoshUIStepper @PSBoundParameters)) { Write-PoshUIHost $line } }
}

Export-ModuleMember -Function @(
    'New-PoshUIStepper', 'Add-PoshUIStep', 'Set-PoshUIStep', 'Format-PoshUIStepper', 'Show-PoshUIStepper'
)
