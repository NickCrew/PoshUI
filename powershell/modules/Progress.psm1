#Requires -Version 7.6
# Native independent progress models and rendering for PoshUI.

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Configuration.psm1') -ErrorAction Stop
Set-Alias -Name Write-Host -Value Write-PoshUIHost -Scope Script
$script:PoshUIStyle = Get-PoshUIStyleInternal

# ============================================================================
# Configuration
# ============================================================================

$script:PO_PROGRESS_CONFIGURATION = Get-PoshUIConfiguration

function New-PoshUIProgress {
    <#
    .SYNOPSIS
        Creates an independent progress model

    .DESCRIPTION
        Creates an in-memory progress model with its own total, current value,
        label, width, start time, and rendering characters. The model has no
        terminal side effects and can be updated independently of other models.

    .PARAMETER Total
        Total number of work units. Must be at least one.

    .PARAMETER Current
        Initial completed work units. Values above Total are clamped to Total.

    .PARAMETER Label
        Text displayed beside the progress bar.

    .PARAMETER Width
        Number of terminal columns used by the bar body. Defaults to the
        resolved startup configuration.

    .INPUTS
        None.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        PS> New-PoshUIProgress -Total 10

        Creates a ten-unit progress model.

    .EXAMPLE
        PS> New-PoshUIProgress -Total 100 -Current 25 -Label 'Build'

        Creates a build progress model at 25 percent.

    .EXAMPLE
        PS> $progress = New-PoshUIProgress -Total 4 -Width 10
        PS> $progress | Update-PoshUIProgress -Increment 1

        Creates and updates one independent model.

    .NOTES
        Use Format-PoshUIProgress for effect-free rendering and
        Show-PoshUIProgress for terminal output.

    .LINK
        Format-PoshUIProgress

    .LINK
        Show-PoshUIProgress
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value and does not mutate external state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Total,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Current = 0,

        [AllowEmptyString()]
        [string]$Label = 'Progress',

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width = [int]$script:PO_PROGRESS_CONFIGURATION.Progress.Width
    )

    [pscustomobject]@{
        PSTypeName     = 'PoshUI.Progress'
        Total          = $Total
        Current        = [Math]::Min($Current, $Total)
        Label          = $Label
        Width          = $Width
        StartedAt      = [DateTimeOffset]::UtcNow
        BarCharacter   = [string]$script:PO_PROGRESS_CONFIGURATION.Progress.BarCharacter
        EmptyCharacter = [string]$script:PO_PROGRESS_CONFIGURATION.Progress.EmptyCharacter
    }
}

function Update-PoshUIProgress {
    <#
    .SYNOPSIS
        Updates an independent progress model

    .DESCRIPTION
        Adds an increment to the supplied progress model and clamps the result
        between zero and the model total. The same model is returned for
        continued pipeline composition.

    .PARAMETER Progress
        Progress model created by New-PoshUIProgress.

    .PARAMETER Increment
        Signed number of units to add. The default is one.

    .INPUTS
        System.Management.Automation.PSCustomObject

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE
        PS> Update-PoshUIProgress -Progress $progress

        Advances the model by one unit.

    .EXAMPLE
        PS> $progress | Update-PoshUIProgress -Increment 5

        Advances a pipeline model by five units.

    .EXAMPLE
        PS> $progress | Update-PoshUIProgress -Increment -1 | Format-PoshUIProgress

        Moves the model back one unit and formats it.

    .NOTES
        This command mutates only the supplied in-memory model.

    .LINK
        New-PoshUIProgress
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory progress model.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({ $_.PSTypeNames -contains 'PoshUI.Progress' })]
        [psobject]$Progress,

        [int]$Increment = 1
    )

    process {
        $next = [long]$Progress.Current + $Increment
        $Progress.Current = [int][Math]::Min([Math]::Max($next, 0), $Progress.Total)
        $Progress
    }
}

function Format-PoshUIProgress {
    <#
    .SYNOPSIS
        Formats a progress model without terminal effects

    .DESCRIPTION
        Returns one progress line for the supplied model. It does not write to
        the host, move the cursor, or mutate the model.

    .PARAMETER Progress
        Progress model created by New-PoshUIProgress.

    .INPUTS
        System.Management.Automation.PSCustomObject

    .OUTPUTS
        System.String

    .EXAMPLE
        PS> Format-PoshUIProgress -Progress $progress

        Returns the formatted progress line.

    .EXAMPLE
        PS> $line = $progress | Format-PoshUIProgress

        Captures the line without displaying it.

    .EXAMPLE
        PS> @($first, $second) | Format-PoshUIProgress

        Formats two independent models for composition.

    .NOTES
        Rendering uses the characters captured when the model was created.

    .LINK
        Show-PoshUIProgress
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({ $_.PSTypeNames -contains 'PoshUI.Progress' })]
        [psobject]$Progress
    )

    process {
        $percentage = [int]($Progress.Current * 100 / $Progress.Total)
        $filled = [int]($Progress.Current * $Progress.Width / $Progress.Total)
        $bar = ($Progress.BarCharacter * $filled) + ($Progress.EmptyCharacter * ($Progress.Width - $filled))

        $color = $script:PoshUIStyle.ProgressActive
        if ($percentage -ge 100) {
            $color = $script:PoshUIStyle.Green
        }
        elseif ($percentage -ge 75) {
            $color = $script:PoshUIStyle.Blue
        }
        elseif ($percentage -ge 50) {
            $color = $script:PoshUIStyle.Yellow
        }

        $pct = '{0,3}' -f $percentage
        $line = "$($Progress.Label) ${color}[$bar]$($script:PoshUIStyle.Reset) $pct% ($($Progress.Current)/$($Progress.Total))"
        if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $line } else { ConvertTo-PoshUIPlainText $line }
    }
}

function Show-PoshUIProgress {
    <#
    .SYNOPSIS
        Displays a formatted progress model

    .DESCRIPTION
        Formats the supplied model and writes it through the PoshUI runtime
        boundary. Interactive terminals receive an in-place carriage-return
        update. Plain terminals receive a stable line, and off mode writes
        nothing.

    .PARAMETER Progress
        Progress model created by New-PoshUIProgress.

    .INPUTS
        System.Management.Automation.PSCustomObject

    .OUTPUTS
        None.

    .EXAMPLE
        PS> Show-PoshUIProgress -Progress $progress

        Displays the current model state.

    .EXAMPLE
        PS> $progress | Show-PoshUIProgress

        Displays a pipeline model.

    .EXAMPLE
        PS> $progress | Update-PoshUIProgress | Show-PoshUIProgress

        Advances and displays the model.

    .NOTES
        Use Format-PoshUIProgress when the caller needs composable output.

    .LINK
        Format-PoshUIProgress
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({ $_.PSTypeNames -contains 'PoshUI.Progress' })]
        [psobject]$Progress
    )

    process {
        $line = Format-PoshUIProgress -Progress $Progress
        if (Test-PoshUITerminalControl) {
            Write-PoshUIHost -Object "`r$line" -NoNewline
        }
        else {
            Write-Host $line
        }
    }
}

Export-ModuleMember -Function @(
    'New-PoshUIProgress'
    'Update-PoshUIProgress'
    'Format-PoshUIProgress'
    'Show-PoshUIProgress'
)
