#Requires -Version 7.6

# Runtime policy shared by every PoshUI module. POSH_UI_MODE is the only
# process-level switch: auto, rich, plain, or off. Everything else stays in
# module scope so importing PoshUI does not publish internal state to children.

$script:PoshUICursorOwner = $null
$script:PoshUIDeferredOutput = [System.Collections.Generic.List[string]]::new()
$script:PoshUIStyle = $null

function Enter-PoshUICursorLease {
    param([Parameter(Mandatory)][object]$OwnerId)

    if ($null -ne $script:PoshUICursorOwner -and $script:PoshUICursorOwner -ne $OwnerId) {
        throw [System.InvalidOperationException]::new('Another PoshUI component owns the terminal cursor.')
    }
    $script:PoshUICursorOwner = $OwnerId
}

function Exit-PoshUICursorLease {
    param([Parameter(Mandatory)][object]$OwnerId)

    if ($script:PoshUICursorOwner -ne $OwnerId) { return }
    try {
        $pending = @($script:PoshUIDeferredOutput)
        if (Test-PoshUIOff) {
            Complete-PoshUIDeferredOutput -OwnerId $OwnerId -Count $pending.Count
            return
        }
        foreach ($line in $pending) {
            $rendered = if (Test-PoshUIRich) {
                ConvertTo-PoshUISafeRichText $line
            }
            else {
                ConvertTo-PoshUIPlainText $line
            }
            [Console]::Out.WriteLine($rendered)
        }
        if ($pending.Count -gt 0) {
            Complete-PoshUIDeferredOutput -OwnerId $OwnerId -Count $pending.Count
        }
    }
    finally {
        $script:PoshUICursorOwner = $null
    }
}

function Get-PoshUIDeferredOutput {
    param([Parameter(Mandatory)][object]$OwnerId)

    if ($script:PoshUICursorOwner -ne $OwnerId) {
        throw [System.InvalidOperationException]::new('Only the active cursor owner can inspect deferred output.')
    }
    @($script:PoshUIDeferredOutput)
}

function Complete-PoshUIDeferredOutput {
    param(
        [Parameter(Mandatory)][object]$OwnerId,
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$Count
    )

    if ($script:PoshUICursorOwner -ne $OwnerId) {
        throw [System.InvalidOperationException]::new('Only the active cursor owner can complete deferred output.')
    }
    $removeCount = [Math]::Min($Count, $script:PoshUIDeferredOutput.Count)
    if ($removeCount -gt 0) { $script:PoshUIDeferredOutput.RemoveRange(0, $removeCount) }
}

function Receive-PoshUIDeferredOutput {
    param([Parameter(Mandatory)][object]$OwnerId)

    if ($script:PoshUICursorOwner -ne $OwnerId) {
        throw [System.InvalidOperationException]::new('Only the active cursor owner can receive deferred output.')
    }
    $lines = @(Get-PoshUIDeferredOutput -OwnerId $OwnerId)
    Complete-PoshUIDeferredOutput -OwnerId $OwnerId -Count $lines.Count
    $lines
}

function Get-PoshUIRuntime {
    <#
    .SYNOPSIS
        Gets the active PoshUI terminal capabilities
    .DESCRIPTION
        Resolves the current runtime mode and explains why it was selected.
        The returned value reports redirection, interactive-input, color, and
        terminal-control capabilities without changing terminal state.
    .INPUTS
        None.
    .OUTPUTS
        PoshUI.Runtime.
    .EXAMPLE
        Get-PoshUIRuntime

        Returns the current runtime capabilities.
    .EXAMPLE
        (Get-PoshUIRuntime).Reason

        Explains why auto mode selected rich or plain output.
    .EXAMPLE
        $env:POSH_UI_MODE = 'off'; Get-PoshUIRuntime

        Confirms that display and logging effects are disabled.
    .NOTES
        POSH_UI_MODE accepts auto, rich, plain, or off. Auto mode also honors
        CI, redirected streams, TERM=dumb, and NO_COLOR.
    .LINK
        Get-PoshUIConfiguration
    #>
    [CmdletBinding()]
    [OutputType('PoshUI.Runtime')]
    param()

    $requested = if ([string]::IsNullOrWhiteSpace($env:POSH_UI_MODE)) {
        'auto'
    }
    else {
        $env:POSH_UI_MODE.Trim().ToLowerInvariant()
    }

    if ($requested -notin 'auto', 'rich', 'plain', 'off') {
        if ($script:WarnedInvalidMode -ne $env:POSH_UI_MODE) {
            Write-Warning "Unknown POSH_UI_MODE '$($env:POSH_UI_MODE)'. Using auto."
            $script:WarnedInvalidMode = $env:POSH_UI_MODE
        }
        $requested = 'auto'
    }

    $outputRedirected = try { [Console]::IsOutputRedirected } catch { $true }
    $inputRedirected = try { [Console]::IsInputRedirected } catch { $true }
    $supportsVirtualTerminal = try { [bool]$Host.UI.SupportsVirtualTerminal } catch { $false }
    $terminalAllowsColor = $env:TERM -ne 'dumb' -and -not $env:NO_COLOR
    $ciEnabled = -not [string]::IsNullOrWhiteSpace($env:CI) -and
        $env:CI.Trim().ToLowerInvariant() -notin '0', 'false', 'no', 'off'

    $mode = $requested
    $reason = 'explicit'
    if ($requested -eq 'auto') {
        if ($ciEnabled) {
            $mode = 'plain'
            $reason = 'CI environment'
        }
        elseif ($outputRedirected) {
            $mode = 'plain'
            $reason = 'stdout is redirected'
        }
        elseif (-not $supportsVirtualTerminal) {
            $mode = 'plain'
            $reason = 'host does not advertise virtual terminal support'
        }
        elseif (-not $terminalAllowsColor) {
            $mode = 'plain'
            $reason = 'terminal color is disabled'
        }
        else {
            $mode = 'rich'
            $reason = 'interactive virtual terminal'
        }
    }

    $runtime = [pscustomobject]@{
        RequestedMode = $requested
        Mode = $mode
        Reason = $reason
        Color = $mode -eq 'rich'
        InteractiveInput = $mode -ne 'off' -and -not $inputRedirected -and
            (-not $ciEnabled -or $requested -ne 'auto')
        TerminalControl = $mode -eq 'rich' -and -not $outputRedirected -and $supportsVirtualTerminal
        OutputRedirected = $outputRedirected
        InputRedirected = $inputRedirected
        SupportsVirtualTerminal = $supportsVirtualTerminal
    }
    $runtime.PSObject.TypeNames.Insert(0, 'PoshUI.Runtime')
    $runtime
}

function Test-PoshUIOff {
    (Get-PoshUIRuntime).Mode -eq 'off'
}

function Test-PoshUIRich {
    (Get-PoshUIRuntime).Color
}

function Test-PoshUIInteractive {
    (Get-PoshUIRuntime).InteractiveInput
}

function Test-PoshUITerminalControl {
    (Get-PoshUIRuntime).TerminalControl
}

function Get-PoshUIStyleInternal {
    # Style tokens are mode-neutral. Formatting and display boundaries strip
    # them when the current runtime mode is plain or off, which lets callers
    # change POSH_UI_MODE after import without retaining a stale style cache.
    if ($null -eq $script:PoshUIStyle) {
        $escape = [char]0x1B
        $sequence = {
            param([string]$Code)
            "${escape}[${Code}m"
        }

        $script:PoshUIStyle = [pscustomobject]@{
            Reset          = & $sequence '0'
            Bold           = & $sequence '1'
            Dim            = & $sequence '2'
            Red            = & $sequence '0;31'
            Green          = & $sequence '0;32'
            Yellow         = & $sequence '0;33'
            Blue           = & $sequence '0;34'
            Magenta        = & $sequence '0;35'
            Cyan           = & $sequence '0;36'
            BrightRed      = & $sequence '0;91'
            BoxBorder      = & $sequence '0;34'
            BoxTitle       = (& $sequence '1') + (& $sequence '0;34')
            TableBorder    = & $sequence '0;34'
            TableHeader    = (& $sequence '1') + (& $sequence '0;36')
            PromptAccent   = & $sequence '0;36'
            ProgressActive = & $sequence '0;36'
            ChartBar       = & $sequence '0;34'
            ChartEmpty     = & $sequence '2'
            Bar            = [char]0x2588
            EmptyBar       = [char]0x2591
            Icon           = [pscustomobject]@{
                Success = [char]0x2713
                Error   = [char]0x2717
                Warning = [char]0x26A0
                Info    = [char]0x2139
                Pointer = [char]0x25B8
            }
        }
    }
    $script:PoshUIStyle
}

function Set-PoshUIStyleInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper mutates only the module-owned in-memory style object.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSTypeName('PoshUI.Theme')][psobject]$Theme)

    $style = Get-PoshUIStyleInternal
    $style.Reset = [string]$Theme.Primitive.Reset
    $style.Bold = [string]$Theme.Primitive.Bold
    $style.Dim = [string]$Theme.Primitive.Dim
    $style.Red = [string]$Theme.Semantic.Danger
    $style.Green = [string]$Theme.Semantic.Success
    $style.Yellow = [string]$Theme.Semantic.Warning
    $style.Blue = [string]$Theme.Semantic.Primary
    $style.Magenta = [string]$Theme.Semantic.Accent
    $style.Cyan = [string]$Theme.Semantic.Accent
    $style.BrightRed = [string]$Theme.Semantic.Danger
    $style.BoxBorder = [string]$Theme.Component.Box.Border
    $style.BoxTitle = [string]$Theme.Component.Box.Title
    $style.TableBorder = [string]$Theme.Component.Table.Border
    $style.TableHeader = [string]$Theme.Component.Table.Header
    $style.PromptAccent = [string]$Theme.Component.Prompt.Accent
    $style.ProgressActive = [string]$Theme.Component.Progress.Active
    $style.ChartBar = [string]$Theme.Component.Chart.Bar
    $style.ChartEmpty = [string]$Theme.Component.Chart.Empty
}

function ConvertTo-PoshUIPlainText {
    param([AllowEmptyString()][string]$Text)
    $plain = [regex]::Replace($Text, "`e\][^`a]*(?:`a|`e\\)", '')
    $plain = [regex]::Replace($plain, "`e\[[0-?]*[ -/]*[@-~]", '')
    $plain = [regex]::Replace($plain, "`e[^\x20-\x7e]?", '')
    [regex]::Replace($plain, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')
}

function ConvertTo-PoshUISafeRichText {
    param([AllowEmptyString()][string]$Text)

    $safe = [regex]::Replace($Text, "`e\][^`a]*(?:`a|`e\\)", '')
    $safe = [regex]::Replace($safe, "`e\[[0-?]*[ -/]*[@-~]", {
            param($match)
            if ($match.Value -match "^`e\[[0-9;]*m$") { $match.Value } else { '' }
        })
    $safe = [regex]::Replace($safe, "`e(?!\[[0-9;]*m)", '')
    [regex]::Replace($safe, '[\x00-\x08\x0B\x0C\x0E-\x1A\x1C-\x1F\x7F-\x9F]', '')
}

function Write-PoshUIHost {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [AllowNull()]
        [object[]]$Object,

        [switch]$NoNewline,

        [ConsoleColor]$ForegroundColor,

        [ConsoleColor]$BackgroundColor,

        [object]$Separator = ' ',

        [object]$OwnerId,

        [switch]$TrustedControl,

        [switch]$ErrorStream
    )

    $runtime = Get-PoshUIRuntime
    if ($runtime.Mode -eq 'off') { return }

    $rendered = (@($Object) | ForEach-Object { [string]$_ }) -join [string]$Separator

    if ($null -ne $script:PoshUICursorOwner -and $script:PoshUICursorOwner -ne $OwnerId) {
        $deferred = (ConvertTo-PoshUIPlainText $rendered) -replace "`r", ''
        foreach ($line in ($deferred -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $script:PoshUIDeferredOutput.Add($line) }
        }
        return
    }
    if ($runtime.Mode -eq 'rich' -and -not $TrustedControl) {
        $rendered = ConvertTo-PoshUISafeRichText $rendered
    }
    elseif ($runtime.Mode -ne 'rich') {
        $rendered = ConvertTo-PoshUIPlainText $rendered
    }

    if ($ErrorStream) {
        if ($NoNewline) { [Console]::Error.Write($rendered) } else { [Console]::Error.WriteLine($rendered) }
        return
    }

    # PowerShell strips literal ANSI from Write-Host when stdout is redirected,
    # even when OutputRendering is Ansi. Explicit rich mode is an override, so
    # bypass host rendering at this boundary and preserve the requested bytes.
    if ($runtime.Mode -eq 'rich' -and $runtime.OutputRedirected) {
        if ($NoNewline) {
            [Console]::Out.Write($rendered)
        }
        else {
            [Console]::Out.WriteLine($rendered)
        }
        return
    }

    $parameters = @{ Object = $rendered }
    if ($NoNewline) { $parameters.NoNewline = $true }
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $parameters.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $parameters.BackgroundColor = $BackgroundColor }
    Microsoft.PowerShell.Utility\Write-Host @parameters
}

Export-ModuleMember -Function @(
    'Get-PoshUIRuntime'
    'Test-PoshUIOff'
    'Test-PoshUIRich'
    'Test-PoshUIInteractive'
    'Test-PoshUITerminalControl'
    'Get-PoshUIStyleInternal'
    'Set-PoshUIStyleInternal'
    'ConvertTo-PoshUIPlainText'
    'ConvertTo-PoshUISafeRichText'
    'Write-PoshUIHost'
    'Enter-PoshUICursorLease'
    'Exit-PoshUICursorLease'
    'Get-PoshUIDeferredOutput'
    'Complete-PoshUIDeferredOutput'
    'Receive-PoshUIDeferredOutput'
)
