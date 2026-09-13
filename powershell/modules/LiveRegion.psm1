#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Layout.psm1') -ErrorAction Stop

function Write-PoshUILiveControlInternal {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][object]$OwnerId
    )

    Write-PoshUIHost -Object $Text -NoNewline -OwnerId $OwnerId -TrustedControl
}

function Write-PoshUILiveCursorVisibilityInternal {
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
    if (-not (Test-PoshUITerminalControl)) { return }
    Write-PoshUILiveControlInternal -Text $sequence -OwnerId $OwnerId
}

function Test-PoshUILiveRegionOpenInternal {
    param([Parameter(Mandatory)][PSTypeName('PoshUI.LiveRegion')][psobject]$Region)

    if ($Region.IsClosed) {
        throw [System.InvalidOperationException]::new('The live region is closed.')
    }
}

function ConvertTo-PoshUILiveTextInternal {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $Text } else { ConvertTo-PoshUIPlainText $Text }
}

function Get-PoshUILiveTerminalWidthInternal {
    $terminalWidth = try { [Console]::WindowWidth } catch { 0 }
    if ($terminalWidth -gt 1) { $terminalWidth - 1 } else { 0 }
}

function Get-PoshUILiveWidthInternal {
    param([Parameter(Mandatory)][PSTypeName('PoshUI.LiveRegion')][psobject]$Region)

    $terminalWidth = Get-PoshUILiveTerminalWidthInternal
    $safeTerminalWidth = if ($terminalWidth -gt 0) { $terminalWidth } else { $Region.Width }
    if ($Region.AutoWidth) { return [Math]::Max(1, $safeTerminalWidth) }
    [Math]::Max(1, [Math]::Min($Region.Width, $safeTerminalWidth))
}

function ConvertTo-PoshUILiveLinesInternal {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Width
    )

    $normalized = (ConvertTo-PoshUILiveTextInternal $Text).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`t", '    ')
    foreach ($logicalLine in ($normalized -split "`n", 0, 'RegexMatch')) {
        foreach ($renderedLine in @(Format-PoshUIText -InputObject $logicalLine -Width $Width -Overflow Wrap)) {
            $renderedLine.TrimEnd()
        }
    }
}

function Close-PoshUILiveCursorInternal {
    param(
        [Parameter(Mandatory)][PSTypeName('PoshUI.LiveRegion')][psobject]$Region,
        [switch]$SuppressDeferredOutput
    )

    try {
        if ($Region.CursorHidden) {
            Write-PoshUILiveCursorVisibilityInternal -Visible $true -OwnerId $Region.Id -Force
        }
    }
    finally {
        try {
            if ($SuppressDeferredOutput -and $Region.OwnsCursor) {
                $pending = @(Get-PoshUIDeferredOutput -OwnerId $Region.Id)
                Complete-PoshUIDeferredOutput -OwnerId $Region.Id -Count $pending.Count
            }
        }
        finally {
            Exit-PoshUICursorLease -OwnerId $Region.Id
            $Region.CursorHidden = $false
            $Region.OwnsCursor = $false
            $Region.RenderedLineCount = 0
        }
    }
}

function Write-PoshUILiveRichSnapshotInternal {
    param(
        [Parameter(Mandatory)][PSTypeName('PoshUI.LiveRegion')][psobject]$Region,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Messages,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Lines
    )

    if ($Region.RenderedLineCount -gt 0) {
        Write-PoshUILiveControlInternal -Text ("`e[{0}A" -f $Region.RenderedLineCount) -OwnerId $Region.Id
    }

    foreach ($message in $Messages) {
        Write-PoshUILiveControlInternal -Text "`e[2K$message`n" -OwnerId $Region.Id
    }

    $lineCount = [Math]::Max($Region.RenderedLineCount, $Lines.Count)
    for ($index = 0; $index -lt $lineCount; $index++) {
        $line = if ($index -lt $Lines.Count) { $Lines[$index] } else { '' }
        Write-PoshUILiveControlInternal -Text "`e[2K$line`n" -OwnerId $Region.Id
    }

    if ($lineCount -gt $Lines.Count) {
        Write-PoshUILiveControlInternal -Text ("`e[{0}A" -f ($lineCount - $Lines.Count)) -OwnerId $Region.Id
    }
    $Region.RenderedLineCount = $Lines.Count
}

function New-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Creates an independent live display region.
    .DESCRIPTION
    Creates a typed in-memory model that coordinates independently keyed
    dashboard, progress, spinner, log, and custom content. Creating a model
    does not write to the terminal or mutate environment variables.
    .PARAMETER Name
    A diagnostic name for the region.
    .PARAMETER Title
    Optional text rendered before the keyed content.
    .PARAMETER Width
    Maximum physical terminal width. Zero resolves the current terminal width
    with one column reserved to prevent automatic wrapping.
    .EXAMPLE
    $region = New-PoshUILiveRegion -Name build
    .EXAMPLE
    $region = New-PoshUILiveRegion -Name deploy -Title 'Deployment'
    .EXAMPLE
    New-PoshUILiveRegion status | Format-PoshUILiveRegion
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
        [string]$Name,

        [AllowEmptyString()]
        [string]$Title = '',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Width = 0
    )

    $resolvedWidth = if ($Width -gt 0) { $Width } else {
        $terminalWidth = try { [Console]::WindowWidth } catch { 80 }
        if ($terminalWidth -lt 2) { 80 } else { $terminalWidth - 1 }
    }

    $region = [pscustomobject]@{
        Id                = [guid]::NewGuid()
        Name              = $Name
        Title             = $Title
        Width             = $resolvedWidth
        AutoWidth         = $Width -eq 0
        Entries           = [ordered]@{}
        PendingMessages   = [System.Collections.Generic.List[string]]::new()
        IsOpen            = $false
        IsClosed          = $false
        OwnsCursor        = $false
        CursorHidden      = $false
        RenderedLineCount = 0
    }
    $region.PSObject.TypeNames.Insert(0, 'PoshUI.LiveRegion')
    $region
}

function Set-PoshUILiveRegionContent {
    <#
    .SYNOPSIS
    Sets independently keyed content in a live region.
    .DESCRIPTION
    Adds or replaces one keyed content entry without writing to the terminal.
    Existing keys retain their display order. The supplied region is the only
    state mutated by this command.
    .PARAMETER Region
    The live region returned by New-PoshUILiveRegion.
    .PARAMETER Key
    The stable identity used to add or replace the content.
    .PARAMETER Content
    One or more rendered text lines.
    .PARAMETER Kind
    The semantic content kind.
    .PARAMETER PassThru
    Returns the updated region.
    .EXAMPLE
    Set-PoshUILiveRegionContent $region build 'Compiling' -Kind Progress
    .EXAMPLE
    $region | Set-PoshUILiveRegionContent -Key clock -Content '12:00' -Kind Dashboard
    .EXAMPLE
    Set-PoshUILiveRegionContent $region worker @('Working', 'Please wait') -Kind Spinner -PassThru
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the caller-supplied in-memory live region.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyString()]
        [string[]]$Content,

        [ValidateSet('Dashboard', 'Progress', 'Spinner', 'Log', 'Content')]
        [string]$Kind = 'Content',

        [switch]$PassThru
    )

    process {
        Test-PoshUILiveRegionOpenInternal -Region $Region
        $Region.Entries[$Key] = [pscustomobject]@{
            Key     = $Key
            Kind    = $Kind
            Content = [string[]]@($Content)
        }
        if ($PassThru) { $Region }
    }
}

function Remove-PoshUILiveRegionContent {
    <#
    .SYNOPSIS
    Removes keyed content from a live region.
    .DESCRIPTION
    Removes one entry from the supplied in-memory region without writing to
    the terminal. A missing key is ignored.
    .PARAMETER Region
    The live region to update.
    .PARAMETER Key
    The key to remove.
    .PARAMETER PassThru
    Returns the updated region.
    .EXAMPLE
    Remove-PoshUILiveRegionContent $region spinner
    .EXAMPLE
    $region | Remove-PoshUILiveRegionContent -Key progress
    .EXAMPLE
    Remove-PoshUILiveRegionContent $region old -PassThru
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [switch]$PassThru
    )

    process {
        Test-PoshUILiveRegionOpenInternal -Region $Region
        if ($PSCmdlet.ShouldProcess($Region.Name, "Remove live content '$Key'")) {
            $Region.Entries.Remove($Key)
        }
        if ($PassThru) { $Region }
    }
}

function Add-PoshUILiveRegionMessage {
    <#
    .SYNOPSIS
    Queues a durable message above a live region.
    .DESCRIPTION
    Adds log or status lines to the region's pending transcript. The next Show
    or Update call writes each message once before the current live content.
    .PARAMETER Region
    The live region that owns the message queue.
    .PARAMETER Message
    One or more durable transcript lines.
    .PARAMETER PassThru
    Returns the updated region.
    .EXAMPLE
    Add-PoshUILiveRegionMessage $region 'Build started'
    .EXAMPLE
    $region | Add-PoshUILiveRegionMessage -Message @('Step 1', 'Step 2')
    .EXAMPLE
    Add-PoshUILiveRegionMessage $region 'Complete' -PassThru
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [string[]]$Message,

        [switch]$PassThru
    )

    process {
        Test-PoshUILiveRegionOpenInternal -Region $Region
        foreach ($line in $Message) { $Region.PendingMessages.Add($line) }
        if ($PassThru) { $Region }
    }
}

function Format-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Formats a live region without terminal effects.
    .DESCRIPTION
    Returns the title and keyed content in stable insertion order. Formatting
    does not acquire the cursor, consume messages, or mutate the region.
    .PARAMETER Region
    The live region to format.
    .PARAMETER IncludeMessages
    Includes pending durable messages before the live content.
    .EXAMPLE
    Format-PoshUILiveRegion $region
    .EXAMPLE
    $lines = $region | Format-PoshUILiveRegion
    .EXAMPLE
    Format-PoshUILiveRegion $region -IncludeMessages
    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [switch]$IncludeMessages
    )

    process {
        $width = Get-PoshUILiveWidthInternal -Region $Region
        if ($IncludeMessages) {
            foreach ($message in $Region.PendingMessages) {
                ConvertTo-PoshUILiveLinesInternal -Text $message -Width $width
            }
        }
        if (-not [string]::IsNullOrEmpty($Region.Title)) {
            ConvertTo-PoshUILiveLinesInternal -Text $Region.Title -Width $width
        }
        foreach ($entry in $Region.Entries.Values) {
            foreach ($line in $entry.Content) {
                ConvertTo-PoshUILiveLinesInternal -Text $line -Width $width
            }
        }
    }
}

function Show-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Displays the current live region snapshot.
    .DESCRIPTION
    Uses one cursor owner for rich terminal updates. Plain mode emits a stable
    append-only snapshot, and off mode emits nothing. Pending messages are
    written once and retained above subsequent rich updates.
    .PARAMETER Region
    The live region to display.
    .EXAMPLE
    Show-PoshUILiveRegion $region
    .EXAMPLE
    $region | Show-PoshUILiveRegion
    .EXAMPLE
    Set-PoshUILiveRegionContent $region job 'Running'; Show-PoshUILiveRegion $region
    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region
    )

    process {
        Test-PoshUILiveRegionOpenInternal -Region $Region
        $runtime = Get-PoshUIRuntime
        $terminalControl = Test-PoshUITerminalControl
        if ($Region.OwnsCursor -and -not $terminalControl) {
            Close-PoshUILiveCursorInternal -Region $Region -SuppressDeferredOutput:($runtime.Mode -eq 'off')
        }
        if ($runtime.Mode -eq 'off') {
            $Region.IsOpen = $false
            return
        }

        try {
            if ($terminalControl) {
                Enter-PoshUICursorLease -OwnerId $Region.Id
                $Region.OwnsCursor = $true
                $width = Get-PoshUILiveWidthInternal -Region $Region
                $deferred = [string[]]@(Get-PoshUIDeferredOutput -OwnerId $Region.Id)
                $messages = [string[]]@(
                    @($deferred) + @($Region.PendingMessages) |
                        ForEach-Object { ConvertTo-PoshUILiveLinesInternal -Text $_ -Width $width }
                )
                $lines = [string[]]@(Format-PoshUILiveRegion -Region $Region)
                if (-not $Region.CursorHidden) {
                    Write-PoshUILiveCursorVisibilityInternal -Visible $false -OwnerId $Region.Id
                    $Region.CursorHidden = $true
                }
                Write-PoshUILiveRichSnapshotInternal -Region $Region -Messages $messages -Lines $lines
                Complete-PoshUIDeferredOutput -OwnerId $Region.Id -Count $deferred.Count
            }
            else {
                $width = Get-PoshUILiveWidthInternal -Region $Region
                $messages = [string[]]@($Region.PendingMessages | ForEach-Object {
                        ConvertTo-PoshUILiveLinesInternal -Text $_ -Width $width
                    })
                $lines = [string[]]@(Format-PoshUILiveRegion -Region $Region)
                foreach ($message in $messages) { Write-PoshUIHost $message }
                foreach ($line in $lines) { Write-PoshUIHost $line }
            }
            $Region.PendingMessages.Clear()
            $Region.IsOpen = $true
        }
        catch {
            Close-PoshUILiveRegion -Region $Region
            throw
        }
    }
}

function Update-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Updates keyed content and displays the live region.
    .DESCRIPTION
    Combines the explicit model mutation and display boundaries for one keyed
    update. The region is closed automatically if display fails.
    .PARAMETER Region
    The live region to update.
    .PARAMETER Key
    The stable identity of the content.
    .PARAMETER Content
    One or more replacement content lines.
    .PARAMETER Kind
    The semantic content kind.
    .EXAMPLE
    Update-PoshUILiveRegion $region progress '50%' -Kind Progress
    .EXAMPLE
    $region | Update-PoshUILiveRegion -Key spinner -Content 'Working' -Kind Spinner
    .EXAMPLE
    Update-PoshUILiveRegion $region dashboard @('Jobs: 3', 'Errors: 0') -Kind Dashboard
    .OUTPUTS
    None
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only the supplied model before displaying it.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyString()]
        [string[]]$Content,

        [ValidateSet('Dashboard', 'Progress', 'Spinner', 'Log', 'Content')]
        [string]$Kind = 'Content'
    )

    process {
        Set-PoshUILiveRegionContent -Region $Region -Key $Key -Content $Content -Kind $Kind
        Show-PoshUILiveRegion -Region $Region
    }
}

function Close-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Closes a live region and restores cursor visibility.
    .DESCRIPTION
    Releases terminal ownership and restores the cursor in a finally block.
    Repeated calls are safe. By default, the last rendered snapshot remains in
    the transcript.
    .PARAMETER Region
    The live region to close.
    .PARAMETER Clear
    Clears the currently rendered rich-terminal lines before closing.
    .EXAMPLE
    Close-PoshUILiveRegion $region
    .EXAMPLE
    $region | Close-PoshUILiveRegion -Clear
    .EXAMPLE
    try { Show-PoshUILiveRegion $region } finally { Close-PoshUILiveRegion $region }
    .OUTPUTS
    None
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [switch]$Clear
    )

    process {
        if ($Region.IsClosed) { return }
        try {
            if ($Region.OwnsCursor) {
                $width = Get-PoshUILiveWidthInternal -Region $Region
                $pending = [string[]]@(Get-PoshUIDeferredOutput -OwnerId $Region.Id)
                $deferred = [string[]]@(
                    $pending | ForEach-Object {
                        ConvertTo-PoshUILiveLinesInternal -Text $_ -Width $width
                    }
                )
                if ($deferred.Count -gt 0) {
                    $lines = [string[]]@(Format-PoshUILiveRegion -Region $Region)
                    Write-PoshUILiveRichSnapshotInternal -Region $Region -Messages $deferred -Lines $lines
                    Complete-PoshUIDeferredOutput -OwnerId $Region.Id -Count $pending.Count
                }
            }
            if ($Clear -and $Region.OwnsCursor -and $Region.RenderedLineCount -gt 0 -and
                $PSCmdlet.ShouldProcess($Region.Name, 'Clear live region')) {
                Write-PoshUILiveControlInternal -Text ("`e[{0}A" -f $Region.RenderedLineCount) -OwnerId $Region.Id
                for ($index = 0; $index -lt $Region.RenderedLineCount; $index++) {
                    Write-PoshUILiveControlInternal -Text "`e[2K`n" -OwnerId $Region.Id
                }
            }
        }
        finally {
            try {
                Close-PoshUILiveCursorInternal -Region $Region
            }
            finally {
                $Region.IsOpen = $false
                $Region.IsClosed = $true
            }
        }
    }
}

function Invoke-PoshUILiveRegion {
    <#
    .SYNOPSIS
    Runs work with guaranteed live-region cleanup.
    .DESCRIPTION
    Invokes a script block with the supplied region and always closes the
    region in a finally block. Cursor restoration therefore occurs after
    success, cancellation exceptions, and other exceptions.
    .PARAMETER Region
    The live region passed as the first script-block argument.
    .PARAMETER ScriptBlock
    Work to invoke while the region is active.
    .PARAMETER ArgumentList
    Optional arguments passed after the region.
    .EXAMPLE
    Invoke-PoshUILiveRegion $region { param($live) Show-PoshUILiveRegion $live }
    .EXAMPLE
    $result = Invoke-PoshUILiveRegion $region { param($live, $name) $name } -ArgumentList build
    .EXAMPLE
    Invoke-PoshUILiveRegion $region { throw 'Stopped' }
    .OUTPUTS
    System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('PoshUI.LiveRegion')]
        [psobject]$Region,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        [scriptblock]$ScriptBlock,

        [Parameter(Position = 2)]
        [AllowEmptyCollection()]
        [object[]]$ArgumentList = @()
    )

    Test-PoshUILiveRegionOpenInternal -Region $Region
    try {
        & $ScriptBlock $Region @ArgumentList
    }
    finally {
        Close-PoshUILiveRegion -Region $Region
    }
}

Export-ModuleMember -Function @(
    'New-PoshUILiveRegion'
    'Set-PoshUILiveRegionContent'
    'Remove-PoshUILiveRegionContent'
    'Add-PoshUILiveRegionMessage'
    'Format-PoshUILiveRegion'
    'Show-PoshUILiveRegion'
    'Update-PoshUILiveRegion'
    'Close-PoshUILiveRegion'
    'Invoke-PoshUILiveRegion'
)
