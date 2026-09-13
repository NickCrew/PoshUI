#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop

$script:PoshUIStyle = Get-PoshUIStyleInternal

function Write-PoshUIPromptInternal {
    param(
        [Parameter(Mandatory)][string]$Message,
        [AllowEmptyString()][string]$DefaultText = ''
    )

    $suffix = if ($DefaultText) { " $($script:PoshUIStyle.Dim)($DefaultText)$($script:PoshUIStyle.Reset)" } else { '' }
    Write-PoshUIHost -NoNewline "$($script:PoshUIStyle.PromptAccent)?$($script:PoshUIStyle.Reset) $($script:PoshUIStyle.Bold)$Message$($script:PoshUIStyle.Reset)$suffix $($script:PoshUIStyle.PromptAccent)>$($script:PoshUIStyle.Reset) "
}

function Write-PoshUIPromptErrorInternal {
    param([Parameter(Mandatory)][string]$Message)
    Write-PoshUIHost "$($script:PoshUIStyle.Red)$($script:PoshUIStyle.Icon.Error) $Message$($script:PoshUIStyle.Reset)"
}

function Read-PoshUIText {
    <#
    .SYNOPSIS
        Reads validated text from an interactive terminal
    .DESCRIPTION
        Reads one line, applies an optional scriptblock validator, and returns
        the accepted text. Redirected input returns an explicit default or
        throws instead of blocking.
    .PARAMETER Message
        Prompt shown before reading input.
    .PARAMETER Default
        Value returned for empty or redirected input.
    .PARAMETER Validator
        Scriptblock that receives the candidate text and returns a Boolean.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Read-PoshUIText -Message 'Service name'
    .EXAMPLE
        Read-PoshUIText -Message 'Region' -Default east
    .EXAMPLE
        Read-PoshUIText -Message 'Code' -Validator { param($value) $value.Length -eq 4 }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [AllowEmptyString()][string]$Default,
        [scriptblock]$Validator
    )

    if (-not (Test-PoshUIInteractive)) {
        if ($PSBoundParameters.ContainsKey('Default')) { return $Default }
        throw [InvalidOperationException]::new('Cannot read text because interactive input is unavailable. Supply -Default or use an interactive host.')
    }

    while ($true) {
        Write-PoshUIPromptInternal -Message $Message -DefaultText $Default
        $value = [Console]::ReadLine()
        if ([string]::IsNullOrEmpty($value) -and $PSBoundParameters.ContainsKey('Default')) { $value = $Default }
        if ([string]::IsNullOrEmpty($value)) {
            Write-PoshUIPromptErrorInternal 'Input cannot be empty.'
            continue
        }
        if ($Validator -and -not (& $Validator $value)) {
            Write-PoshUIPromptErrorInternal 'Input did not pass validation.'
            continue
        }
        return $value
    }
}

function Read-PoshUIPassword {
    <#
    .SYNOPSIS
        Reads a password without exposing plaintext
    .DESCRIPTION
        Reads masked key input into a read-only SecureString. Escape or Ctrl+C
        cancels and returns no value. Redirected input throws instead of blocking.
    .PARAMETER Message
        Prompt shown before reading the password.
    .INPUTS
        None.
    .OUTPUTS
        System.Security.SecureString.
    .EXAMPLE
        Read-PoshUIPassword -Message 'Password'
    .EXAMPLE
        $secret = Read-PoshUIPassword 'Artifactory token'
    .EXAMPLE
        $credential = [PSCredential]::new('user', (Read-PoshUIPassword 'Token'))
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param([Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message)

    if (-not (Test-PoshUIInteractive)) {
        throw [InvalidOperationException]::new('Cannot read a password because interactive input is unavailable.')
    }

    Write-PoshUIPromptInternal -Message $Message
    $password = [securestring]::new()
    while ($true) {
        $keyInfo = [Console]::ReadKey($true)
        if ($keyInfo.Key -eq [ConsoleKey]::Enter) { break }
        if ($keyInfo.Key -eq [ConsoleKey]::Escape -or
            ($keyInfo.Key -eq [ConsoleKey]::C -and ($keyInfo.Modifiers -band [ConsoleModifiers]::Control))) {
            Write-PoshUIHost ''
            $password.Dispose()
            return
        }
        if ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
            if ($password.Length -gt 0) {
                $password.RemoveAt($password.Length - 1)
                [Console]::Write("`b `b")
            }
            continue
        }
        if (-not [char]::IsControl($keyInfo.KeyChar)) {
            $password.AppendChar($keyInfo.KeyChar)
            [Console]::Write('*')
        }
    }
    Write-PoshUIHost ''
    $password.MakeReadOnly()
    $password
}

function Confirm-PoshUIChoice {
    <#
    .SYNOPSIS
        Reads a yes or no confirmation
    .DESCRIPTION
        Returns a Boolean response from an interactive terminal. Noninteractive
        calls return false so automation never grants confirmation implicitly.
    .PARAMETER Message
        Confirmation question.
    .PARAMETER Default
        Response used when Enter is pressed without text.
    .INPUTS
        None.
    .OUTPUTS
        System.Boolean.
    .EXAMPLE
        Confirm-PoshUIChoice -Message 'Continue?'
    .EXAMPLE
        Confirm-PoshUIChoice -Message 'Delete file?' -Default No
    .EXAMPLE
        if (Confirm-PoshUIChoice 'Deploy?') { 'approved' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [ValidateSet('Yes', 'No')][string]$Default = 'Yes'
    )

    if (-not (Test-PoshUIInteractive)) { return $false }
    $hint = if ($Default -eq 'Yes') { 'Y/n' } else { 'y/N' }
    while ($true) {
        Write-PoshUIPromptInternal -Message $Message -DefaultText $hint
        $response = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($response)) { return $Default -eq 'Yes' }
        switch ($response.Trim().ToLowerInvariant()) {
            { $_ -in 'y', 'yes' } { return $true }
            { $_ -in 'n', 'no' } { return $false }
            default { Write-PoshUIPromptErrorInternal 'Enter yes or no.' }
        }
    }
}

function Select-PoshUIOption {
    <#
    .SYNOPSIS
        Selects one value from a numbered list
    .DESCRIPTION
        Displays a numbered option list and returns the selected value.
        Noninteractive calls cancel and return no value.
    .PARAMETER Message
        Prompt shown above the list.
    .PARAMETER Option
        Values available for selection.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Select-PoshUIOption -Message 'Environment' -Option int, qa, stage
    .EXAMPLE
        $choice = Select-PoshUIOption 'Region' east, west
    .EXAMPLE
        Select-PoshUIOption -Message 'Action' -Option build, test
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string[]]$Option
    )

    if (-not (Test-PoshUIInteractive)) { return }
    Write-PoshUIHost "$($script:PoshUIStyle.Bold)$Message$($script:PoshUIStyle.Reset)"
    for ($index = 0; $index -lt $Option.Count; $index++) {
        Write-PoshUIHost ('  {0}) {1}' -f ($index + 1), $Option[$index])
    }
    while ($true) {
        Write-PoshUIPromptInternal -Message "Choose 1-$($Option.Count)"
        $selection = 0
        if ([int]::TryParse([Console]::ReadLine(), [ref]$selection) -and
            $selection -ge 1 -and $selection -le $Option.Count) {
            return $Option[$selection - 1]
        }
        Write-PoshUIPromptErrorInternal 'Enter one of the listed numbers.'
    }
}

function Select-PoshUIMultipleOption {
    <#
    .SYNOPSIS
        Selects zero or more values from a numbered list
    .DESCRIPTION
        Accepts space-separated option numbers, all, or none and returns the
        selected values. Noninteractive calls return an empty array.
    .PARAMETER Message
        Prompt shown above the list.
    .PARAMETER Option
        Values available for selection.
    .INPUTS
        None.
    .OUTPUTS
        System.String[].
    .EXAMPLE
        Select-PoshUIMultipleOption -Message 'Checks' -Option lint, test, build
    .EXAMPLE
        $checks = Select-PoshUIMultipleOption 'Checks' unit, integration
    .EXAMPLE
        Select-PoshUIMultipleOption -Message 'Targets' -Option api, worker
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string[]]$Option
    )

    if (-not (Test-PoshUIInteractive)) { return ,([string[]]@()) }
    Write-PoshUIHost "$($script:PoshUIStyle.Bold)$Message$($script:PoshUIStyle.Reset)"
    for ($index = 0; $index -lt $Option.Count; $index++) {
        Write-PoshUIHost ('  {0}) {1}' -f ($index + 1), $Option[$index])
    }
    while ($true) {
        Write-PoshUIPromptInternal -Message 'Choose numbers, all, or none'
        $response = ([Console]::ReadLine()).Trim()
        if ($response -eq 'all') { return ,([string[]]$Option) }
        if (-not $response -or $response -eq 'none') { return ,([string[]]@()) }
        $indexes = @($response -split '\s+' | ForEach-Object {
                $number = 0
                if (-not [int]::TryParse($_, [ref]$number) -or $number -lt 1 -or $number -gt $Option.Count) {
                    return $null
                }
                $number - 1
            })
        if ($indexes -contains $null) {
            Write-PoshUIPromptErrorInternal 'Enter only listed numbers, all, or none.'
            continue
        }
        return ,([string[]]@($indexes | Select-Object -Unique | ForEach-Object { $Option[$_] }))
    }
}

function Read-PoshUINumber {
    <#
    .SYNOPSIS
        Reads a number within optional bounds
    .DESCRIPTION
        Parses input with invariant culture and returns a Double. Redirected
        input returns an explicit default or throws instead of blocking.
    .PARAMETER Message
        Prompt shown before reading input.
    .PARAMETER Minimum
        Inclusive lower bound.
    .PARAMETER Maximum
        Inclusive upper bound.
    .PARAMETER Default
        Value returned for empty or redirected input.
    .INPUTS
        None.
    .OUTPUTS
        System.Double.
    .EXAMPLE
        Read-PoshUINumber -Message 'Retries'
    .EXAMPLE
        Read-PoshUINumber -Message 'Percent' -Minimum 0 -Maximum 100
    .EXAMPLE
        Read-PoshUINumber -Message 'Workers' -Default 4
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [Nullable[double]]$Minimum,
        [Nullable[double]]$Maximum,
        [Nullable[double]]$Default
    )

    if ($null -ne $Minimum -and $null -ne $Maximum -and $Minimum -gt $Maximum) {
        throw 'Minimum cannot be greater than Maximum.'
    }
    if (-not (Test-PoshUIInteractive)) {
        if ($PSBoundParameters.ContainsKey('Default')) { return [double]$Default }
        throw [InvalidOperationException]::new('Cannot read a number because interactive input is unavailable. Supply -Default or use an interactive host.')
    }

    $culture = [Globalization.CultureInfo]::InvariantCulture
    while ($true) {
        $defaultText = if ($PSBoundParameters.ContainsKey('Default')) { [string]$Default } else { '' }
        Write-PoshUIPromptInternal -Message $Message -DefaultText $defaultText
        $inputText = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($inputText) -and $PSBoundParameters.ContainsKey('Default')) { return [double]$Default }
        $number = 0.0
        if (-not [double]::TryParse($inputText, [Globalization.NumberStyles]::Float, $culture, [ref]$number)) {
            Write-PoshUIPromptErrorInternal 'Enter a valid number.'
            continue
        }
        if ($null -ne $Minimum -and $number -lt $Minimum) {
            Write-PoshUIPromptErrorInternal "Enter a number greater than or equal to $Minimum."
            continue
        }
        if ($null -ne $Maximum -and $number -gt $Maximum) {
            Write-PoshUIPromptErrorInternal "Enter a number less than or equal to $Maximum."
            continue
        }
        return $number
    }
}

function Read-PoshUIFilePath {
    <#
    .SYNOPSIS
        Reads the path of an existing file
    .DESCRIPTION
        Repeats until the caller supplies an existing file matching the optional
        wildcard pattern. Redirected input throws instead of blocking.
    .PARAMETER Message
        Prompt shown before reading the path.
    .PARAMETER Pattern
        Optional wildcard matched against the supplied path.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Read-PoshUIFilePath -Message 'Configuration file'
    .EXAMPLE
        Read-PoshUIFilePath -Message 'Script' -Pattern '*.ps1'
    .EXAMPLE
        $path = Read-PoshUIFilePath 'Manifest'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message,
        [ValidateNotNullOrEmpty()][string]$Pattern = '*'
    )

    if (-not (Test-PoshUIInteractive)) {
        throw [InvalidOperationException]::new('Cannot read a file path because interactive input is unavailable.')
    }
    while ($true) {
        Write-PoshUIPromptInternal -Message $Message
        $path = [Console]::ReadLine()
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and $path -like $Pattern) { return $path }
        Write-PoshUIPromptErrorInternal "File not found or does not match '$Pattern': $path"
    }
}

function Read-PoshUIDirectoryPath {
    <#
    .SYNOPSIS
        Reads the path of an existing directory
    .DESCRIPTION
        Repeats until the caller supplies an existing directory. Redirected
        input throws instead of blocking.
    .PARAMETER Message
        Prompt shown before reading the path.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        Read-PoshUIDirectoryPath -Message 'Workspace'
    .EXAMPLE
        $path = Read-PoshUIDirectoryPath 'Output directory'
    .EXAMPLE
        Read-PoshUIDirectoryPath -Message 'Repository root'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$Message)

    if (-not (Test-PoshUIInteractive)) {
        throw [InvalidOperationException]::new('Cannot read a directory path because interactive input is unavailable.')
    }
    while ($true) {
        Write-PoshUIPromptInternal -Message $Message
        $path = [Console]::ReadLine()
        if (Test-Path -LiteralPath $path -PathType Container) { return $path }
        Write-PoshUIPromptErrorInternal "Directory not found: $path"
    }
}

Export-ModuleMember -Function @(
    'Read-PoshUIText'
    'Read-PoshUIPassword'
    'Confirm-PoshUIChoice'
    'Select-PoshUIOption'
    'Select-PoshUIMultipleOption'
    'Read-PoshUINumber'
    'Read-PoshUIFilePath'
    'Read-PoshUIDirectoryPath'
)
