#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Configuration.psm1') -ErrorAction Stop
$script:PoshUIStyle = Get-PoshUIStyleInternal

function ConvertTo-PoshUILogBooleanInternal {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in '1', 'true', 'yes', 'on' } { $true }
        { $_ -in '0', 'false', 'no', 'off' } { $false }
        default { $Default }
    }
}

function Get-PoshUILogLevelValueInternal {
    param([Parameter(Mandatory)][string]$Level)

    switch ($Level.ToUpperInvariant()) {
        'DEBUG' { 0 }
        'INFO' { 1 }
        'WARNING' { 2 }
        'ERROR' { 3 }
        'FATAL' { 4 }
    }
}

function Get-PoshUILogColorInternal {
    param([Parameter(Mandatory)][string]$Level)

    switch ($Level) {
        'DEBUG' { $script:PoshUIStyle.Cyan }
        'INFO' { $script:PoshUIStyle.Green }
        'WARNING' { $script:PoshUIStyle.Yellow }
        'ERROR' { $script:PoshUIStyle.Red }
        'FATAL' { $script:PoshUIStyle.BrightRed }
    }
}

function Resolve-PoshUILogCanonicalPathInternal {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    $segments = $fullPath.Substring($root.Length).Split(
        [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar),
        [StringSplitOptions]::RemoveEmptyEntries
    )
    $resolved = $root
    foreach ($segment in $segments) {
        $candidate = Join-Path $resolved $segment
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            $resolved = $candidate
            continue
        }
        $target = if ($item.LinkType -and $item.PSObject.Methods.Name -contains 'ResolveLinkTarget') {
            $item.ResolveLinkTarget($true)
        }
        $resolved = if ($null -ne $target) { $target.FullName } else { $item.FullName }
    }
    [IO.Path]::GetFullPath($resolved)
}

function Invoke-PoshUILogLockInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Operation
    )

    $identity = Resolve-PoshUILogCanonicalPathInternal -Path $Path
    if ($IsWindows) { $identity = $identity.ToUpperInvariant() }
    $bytes = [Text.Encoding]::UTF8.GetBytes($identity)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $mutex = [Threading.Mutex]::new($false, "PoshUI.Log.$hash")
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw [TimeoutException]::new("Timed out waiting to write PoshUI log file '$Path'.")
        }
        & $Operation
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Copy-PoshUILogConfigurationInternal {
    [pscustomobject]@{
        PSTypeName    = 'PoshUI.LogConfiguration'
        Level         = $script:PoshUILogConfiguration.Level
        FilePath      = $script:PoshUILogConfiguration.FilePath
        ConsoleOutput = $script:PoshUILogConfiguration.ConsoleOutput
        MaximumSize   = $script:PoshUILogConfiguration.MaximumSize
        MaximumFiles  = $script:PoshUILogConfiguration.MaximumFiles
    }
}

function Invoke-PoshUILogRotationInternal {
    param([Parameter(Mandatory)][string]$Path)

    $maximumFiles = $script:PoshUILogConfiguration.MaximumFiles
    $directory = Split-Path -Parent $Path
    $leafName = Split-Path -Leaf $Path
    $archivePattern = '^' + [regex]::Escape($leafName) + '\.(?<index>\d+)$'
    foreach ($archive in Get-ChildItem -LiteralPath $directory -File -ErrorAction Stop) {
        $match = [regex]::Match($archive.Name, $archivePattern)
        if ($match.Success -and [int]$match.Groups['index'].Value -gt $maximumFiles) {
            Remove-Item -LiteralPath $archive.FullName -Force -ErrorAction Stop
        }
    }
    $oldest = "$Path.$maximumFiles"
    if (Test-Path -LiteralPath $oldest -PathType Leaf) {
        Remove-Item -LiteralPath $oldest -Force -ErrorAction Stop
    }
    for ($index = $maximumFiles - 1; $index -ge 1; $index--) {
        $source = "$Path.$index"
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Move-Item -LiteralPath $source -Destination "$Path.$($index + 1)" -Force -ErrorAction Stop
        }
    }
    Move-Item -LiteralPath $Path -Destination "$Path.1" -Force -ErrorAction Stop
}

function Write-PoshUILogFileInternal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Json
    )

    $encoding = [Text.UTF8Encoding]::new($false)
    $record = $Json + [Environment]::NewLine
    try {
        Invoke-PoshUILogLockInternal -Path $Path -Operation {
            $directory = Split-Path -Parent $Path
            if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
                New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
            }
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                $currentLength = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
                $incomingLength = $encoding.GetByteCount($record)
                if ($currentLength -gt 0 -and
                    $currentLength + $incomingLength -gt $script:PoshUILogConfiguration.MaximumSize) {
                    Invoke-PoshUILogRotationInternal -Path $Path
                }
            }
            [IO.File]::AppendAllText($Path, $record, $encoding)
        }
    }
    catch {
        throw [IO.IOException]::new("Failed to append PoshUI log file '$Path': $($_.Exception.Message)", $_.Exception)
    }
}

$startupLogging = (Get-PoshUIConfiguration).Logging
$startupLevel = ([string]$startupLogging.Level).Trim().ToUpperInvariant()
if ($startupLevel -eq 'WARN') { $startupLevel = 'WARNING' }
if ($startupLevel -notin 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL') { $startupLevel = 'INFO' }
$startupFilePath = if ([string]::IsNullOrWhiteSpace([string]$startupLogging.File)) {
    ''
}
else {
    [IO.Path]::GetFullPath([string]$startupLogging.File)
}
$script:PoshUILogConfiguration = [pscustomobject]@{
    Level         = $startupLevel
    FilePath      = if (ConvertTo-PoshUILogBooleanInternal -Value ([string]$startupLogging.ToFile) -Default $false) {
        $startupFilePath
    }
    else { '' }
    ConsoleOutput = ConvertTo-PoshUILogBooleanInternal -Value ([string]$startupLogging.ToConsole) -Default $true
    MaximumSize   = [long]$startupLogging.MaximumSize
    MaximumFiles  = [int]$startupLogging.MaximumFiles
}

function Set-PoshUILogConfiguration {
    <#
    .SYNOPSIS
        Updates the PoshUI application logging configuration
    .DESCRIPTION
        Updates only the supplied settings for terminal output and the optional
        synchronous JSONL file sink. A non-empty file path enables the sink and
        creates its parent directory. An empty path disables file output.
        Configuration is held in module scope and does not mutate environment
        variables.
    .PARAMETER Level
        Minimum accepted level: Debug, Info, Warning, Error, or Fatal.
    .PARAMETER FilePath
        JSONL file path. An empty value disables the file sink.
    .PARAMETER ConsoleOutput
        Whether accepted events are also rendered to the terminal.
    .PARAMETER MaximumSize
        Maximum active-file size in bytes before the next event rotates it.
    .PARAMETER MaximumFiles
        Number of numbered archive files retained beside the active file.
    .PARAMETER PassThru
        Returns a copy of the resulting configuration.
    .INPUTS
        None.
    .OUTPUTS
        PoshUI.LogConfiguration when PassThru is supplied. Otherwise none.
    .EXAMPLE
        Set-PoshUILogConfiguration -Level Info -FilePath ./logs/app.jsonl
    .EXAMPLE
        Set-PoshUILogConfiguration -ConsoleOutput $false -MaximumSize 5MB
    .EXAMPLE
        Set-PoshUILogConfiguration -FilePath '' -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PoshUI.LogConfiguration')]
    param(
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Fatal')]
        [string]$Level,

        [AllowEmptyString()][string]$FilePath,

        [bool]$ConsoleOutput,

        [ValidateRange(1, [long]::MaxValue)][long]$MaximumSize,

        [ValidateRange(1, [int]::MaxValue)][int]$MaximumFiles,

        [switch]$PassThru
    )

    if ($PSCmdlet.ShouldProcess('PoshUI logging configuration', 'Update')) {
        if ($PSBoundParameters.ContainsKey('Level')) {
            $script:PoshUILogConfiguration.Level = $Level.ToUpperInvariant()
        }
        if ($PSBoundParameters.ContainsKey('FilePath')) {
            $resolvedPath = if ([string]::IsNullOrWhiteSpace($FilePath)) { '' } else { [IO.Path]::GetFullPath($FilePath) }
            if ($resolvedPath -and -not (Test-PoshUIOff)) {
                $directory = Split-Path -Parent $resolvedPath
                if ($directory) {
                    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
                }
            }
            $script:PoshUILogConfiguration.FilePath = $resolvedPath
        }
        if ($PSBoundParameters.ContainsKey('ConsoleOutput')) {
            $script:PoshUILogConfiguration.ConsoleOutput = $ConsoleOutput
        }
        if ($PSBoundParameters.ContainsKey('MaximumSize')) {
            $script:PoshUILogConfiguration.MaximumSize = $MaximumSize
        }
        if ($PSBoundParameters.ContainsKey('MaximumFiles')) {
            $script:PoshUILogConfiguration.MaximumFiles = $MaximumFiles
        }
    }
    if ($PassThru) { Copy-PoshUILogConfigurationInternal }
}

function Get-PoshUILogConfiguration {
    <#
    .SYNOPSIS
        Gets the active PoshUI logging configuration
    .DESCRIPTION
        Returns an independent copy of the module-scoped logging settings.
        Changing the returned object does not change active logging behavior.
    .INPUTS
        None.
    .OUTPUTS
        PoshUI.LogConfiguration.
    .EXAMPLE
        Get-PoshUILogConfiguration
    .EXAMPLE
        (Get-PoshUILogConfiguration).Level
    .EXAMPLE
        Get-PoshUILogConfiguration | Format-List
    #>
    [CmdletBinding()]
    [OutputType('PoshUI.LogConfiguration')]
    param()

    Copy-PoshUILogConfigurationInternal
}

function Write-PoshUILog {
    <#
    .SYNOPSIS
        Writes one structured PoshUI application log event
    .DESCRIPTION
        Creates one event, applies level filtering, renders a human-readable
        terminal line when enabled, and appends one compact JSON object to the
        configured local file sink. Fatal is a severity level and never exits
        the caller. Off mode suppresses both destinations.
    .PARAMETER Level
        Event severity: Debug, Info, Warning, Error, or Fatal.
    .PARAMETER Message
        Human-readable event message. Terminal control sequences are removed.
    .PARAMETER Data
        Optional structured fields serialized verbatim beneath the data
        property. Do not include passwords, tokens, or other credentials.
    .PARAMETER Exception
        Optional exception serialized as type, message, and stackTrace fields.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        Write-PoshUILog -Level Info -Message 'Deployment started'
    .EXAMPLE
        Write-PoshUILog -Level Warning -Message 'Slow health check' -Data @{ seconds = 12 }
    .EXAMPLE
        Write-PoshUILog -Level Error -Message 'Promotion failed' -Exception $_.Exception
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Fatal')]
        [string]$Level,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()][string]$Message,

        [System.Collections.IDictionary]$Data,

        [Exception]$Exception
    )

    if (Test-PoshUIOff) { return }
    $normalizedLevel = $Level.ToUpperInvariant()
    if ((Get-PoshUILogLevelValueInternal -Level $normalizedLevel) -lt
        (Get-PoshUILogLevelValueInternal -Level $script:PoshUILogConfiguration.Level)) {
        return
    }

    $plainMessage = ConvertTo-PoshUIPlainText $Message
    $timestamp = [DateTimeOffset]::Now.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $logEvent = [ordered]@{
        schemaVersion = 1
        timestamp = $timestamp
        level     = $normalizedLevel
        message   = $plainMessage
    }
    if ($null -ne $Data) { $logEvent.data = $Data }
    if ($null -ne $Exception) {
        $logEvent.exception = [ordered]@{
            type       = $Exception.GetType().FullName
            message    = ConvertTo-PoshUIPlainText $Exception.Message
            stackTrace = $Exception.StackTrace
        }
    }

    if ($script:PoshUILogConfiguration.ConsoleOutput) {
        $color = Get-PoshUILogColorInternal -Level $normalizedLevel
        $consoleLine = "$($script:PoshUIStyle.Dim)$timestamp$($script:PoshUIStyle.Reset) ${color}[$normalizedLevel]$($script:PoshUIStyle.Reset) $plainMessage"
        Write-PoshUIHost $consoleLine -ErrorStream:($normalizedLevel -in 'ERROR', 'FATAL')
    }
    if ($script:PoshUILogConfiguration.FilePath) {
        $json = $logEvent | ConvertTo-Json -Compress -Depth 20
        Write-PoshUILogFileInternal -Path $script:PoshUILogConfiguration.FilePath -Json $json
    }
}

function Clear-PoshUILog {
    <#
    .SYNOPSIS
        Clears the active PoshUI JSONL file sink
    .DESCRIPTION
        Truncates the configured active file when it exists. It does not remove
        rotated archives and has no effect when the sink is disabled, missing,
        or PoshUI is off.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        Clear-PoshUILog
    .EXAMPLE
        Set-PoshUILogConfiguration -FilePath ./logs/app.jsonl; Clear-PoshUILog
    .EXAMPLE
        $env:POSH_UI_MODE = 'off'; Clear-PoshUILog
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param()

    if (Test-PoshUIOff) { return }
    $path = $script:PoshUILogConfiguration.FilePath
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    if (-not $PSCmdlet.ShouldProcess($path, 'Clear PoshUI log file')) { return }
    try {
        Invoke-PoshUILogLockInternal -Path $path -Operation {
            [IO.File]::WriteAllText($path, '', [Text.UTF8Encoding]::new($false))
        }
    }
    catch {
        throw [IO.IOException]::new("Failed to clear PoshUI log file '$path': $($_.Exception.Message)", $_.Exception)
    }
}

Export-ModuleMember -Function @(
    'Set-PoshUILogConfiguration'
    'Get-PoshUILogConfiguration'
    'Write-PoshUILog'
    'Clear-PoshUILog'
)
