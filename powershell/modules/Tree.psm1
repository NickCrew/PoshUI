#Requires -Version 7.6

Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -ErrorAction Stop

function ConvertTo-PoshUITreeSafeTextInternal {
    param([AllowEmptyString()][string]$Text)

    if (Test-PoshUIRich) { ConvertTo-PoshUISafeRichText $Text } else { ConvertTo-PoshUIPlainText $Text }
}

function Test-PoshUITreeScalar {
    param([AllowNull()][object]$Value)
    $null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive -or
        $Value -is [decimal] -or $Value -is [datetime] -or $Value -is [guid] -or $Value -is [enum]
}

function Get-PoshUITreeEntry {
    param([Parameter(Mandatory)][object]$Value)
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { [pscustomobject]@{ Label = [string]$key; Value = $Value[$key] } }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            [pscustomobject]@{ Label = "[$index]"; Value = $item }
            $index++
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties | Where-Object MemberType -in NoteProperty, Property, AliasProperty, ScriptProperty) {
        [pscustomobject]@{ Label = $property.Name; Value = $property.Value }
    }
}

function Format-PoshUITree {
    <#
    .SYNOPSIS
    Formats nested objects and collections as a hierarchy
    .DESCRIPTION
    Walks dictionaries, collections, and object properties and returns a stable
    hierarchy without writing to the host. Compact style places scalar values
    beside their labels. Expanded style gives scalar values their own nodes.
    ASCII and Unicode connector sets are explicit and deterministic.
    .PARAMETER InputObject
    Root object, dictionary, or collection to render.
    .PARAMETER RootLabel
    Label for the root node.
    .PARAMETER Style
    Compact or Expanded scalar presentation.
    .PARAMETER CharacterSet
    ASCII or Unicode branch connectors.
    .PARAMETER MaxDepth
    Maximum nested depth before an ellipsis node is emitted.
    .INPUTS
    System.Object
    .OUTPUTS
    System.String
    .EXAMPLE
    Format-PoshUITree -InputObject $config -RootLabel Configuration

    Formats a configuration object with Unicode connectors.
    .EXAMPLE
    Format-PoshUITree -InputObject $plan -Style Expanded -CharacterSet ASCII

    Formats scalar values as child nodes using ASCII connectors.
    .EXAMPLE
    ,@('api', 'worker') | Format-PoshUITree -RootLabel Services -MaxDepth 3

    Formats a collection received from the pipeline.
    .NOTES
    Circular references are reported as a visible circular marker.
    .LINK
    Show-PoshUITree
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][object]$InputObject,
        [ValidateNotNullOrEmpty()][string]$RootLabel = 'Root',
        [ValidateSet('Compact', 'Expanded')][string]$Style = 'Compact',
        [ValidateSet('ASCII', 'Unicode')][string]$CharacterSet = 'Unicode',
        [ValidateRange(1, 100)][int]$MaxDepth = 12
    )
    process {
        $safeRootLabel = ConvertTo-PoshUITreeSafeTextInternal $RootLabel
        $branch = if ($CharacterSet -eq 'Unicode') { '├─ ' } else { '|- ' }
        $lastBranch = if ($CharacterSet -eq 'Unicode') { '└─ ' } else { '\- ' }
        $vertical = if ($CharacterSet -eq 'Unicode') { '│  ' } else { '|  ' }
        $blank = '   '
        $seen = [System.Collections.Generic.HashSet[int]]::new()

        function Add-Child {
            param([object]$Node, [string]$Prefix, [int]$Depth)
            if (Test-PoshUITreeScalar $Node) { return }
            if ($Depth -gt $MaxDepth) { return }

            $identity = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Node)
            if (-not $seen.Add($identity)) { return }
            try {
                $entries = @(Get-PoshUITreeEntry $Node)
                for ($index = 0; $index -lt $entries.Count; $index++) {
                    $entry = $entries[$index]
                    $isLast = $index -eq $entries.Count - 1
                    $connector = if ($isLast) { $lastBranch } else { $branch }
                    $childPrefix = $Prefix + $(if ($isLast) { $blank } else { $vertical })
                    $isScalar = Test-PoshUITreeScalar $entry.Value
                    $entryLabel = ConvertTo-PoshUITreeSafeTextInternal ([string]$entry.Label)
                    $scalarText = if ($null -eq $entry.Value) { '<null>' } else {
                        ConvertTo-PoshUITreeSafeTextInternal ([string]$entry.Value)
                    }
                    $scalarLines = @([regex]::Split($scalarText, "\r\n|\n|\r"))

                    if ($isScalar -and $Style -eq 'Compact' -and $scalarLines.Count -eq 1) {
                        "$Prefix$connector$entryLabel`: $scalarText"
                    }
                    else {
                        "$Prefix$connector$entryLabel"
                        if ($isScalar) {
                            for ($lineIndex = 0; $lineIndex -lt $scalarLines.Count; $lineIndex++) {
                                $lineConnector = if ($lineIndex -eq $scalarLines.Count - 1) { $lastBranch } else { $branch }
                                "$childPrefix$lineConnector$($scalarLines[$lineIndex])"
                            }
                        }
                        elseif ($Depth -ge $MaxDepth) {
                            "$childPrefix$lastBranch…"
                        }
                        else {
                            $childIdentity = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($entry.Value)
                            if ($seen.Contains($childIdentity)) {
                                "$childPrefix$lastBranch<circular>"
                            }
                            else {
                                Add-Child -Node $entry.Value -Prefix $childPrefix -Depth ($Depth + 1)
                            }
                        }
                    }
                }
            }
            finally { [void]$seen.Remove($identity) }
        }

        if (Test-PoshUITreeScalar $InputObject) {
            $text = if ($null -eq $InputObject) { '<null>' } else {
                ConvertTo-PoshUITreeSafeTextInternal ([string]$InputObject)
            }
            $textLines = @([regex]::Split($text, "\r\n|\n|\r"))
            if ($Style -eq 'Compact' -and $textLines.Count -eq 1) { "$safeRootLabel`: $text" }
            else {
                $safeRootLabel
                for ($lineIndex = 0; $lineIndex -lt $textLines.Count; $lineIndex++) {
                    $lineConnector = if ($lineIndex -eq $textLines.Count - 1) { $lastBranch } else { $branch }
                    "$lineConnector$($textLines[$lineIndex])"
                }
            }
        }
        else {
            $safeRootLabel
            Add-Child -Node $InputObject -Prefix '' -Depth 1
        }
    }
}

function Show-PoshUITree {
    <#
    .SYNOPSIS
    Displays nested objects and collections as a hierarchy
    .DESCRIPTION
    Uses Format-PoshUITree to build the render model, then writes each line
    through the shared PoshUI host boundary.
    .PARAMETER InputObject
    Root object, dictionary, or collection to display.
    .PARAMETER RootLabel
    Label for the root node.
    .PARAMETER Style
    Compact or Expanded scalar presentation.
    .PARAMETER CharacterSet
    ASCII or Unicode connectors.
    .PARAMETER MaxDepth
    Maximum rendered nesting depth.
    .INPUTS
    System.Object
    .OUTPUTS
    None
    .EXAMPLE
    Show-PoshUITree -InputObject $config

    Displays a compact Unicode tree.
    .EXAMPLE
    Show-PoshUITree -InputObject $plan -RootLabel Plan -Style Expanded

    Displays an expanded plan hierarchy.
    .EXAMPLE
    Show-PoshUITree -InputObject $results -CharacterSet ASCII -MaxDepth 5

    Displays a bounded ASCII hierarchy.
    .NOTES
    Off mode suppresses host output through Write-PoshUIHost.
    .LINK
    Format-PoshUITree
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][object]$InputObject,
        [ValidateNotNullOrEmpty()][string]$RootLabel = 'Root',
        [ValidateSet('Compact', 'Expanded')][string]$Style = 'Compact',
        [ValidateSet('ASCII', 'Unicode')][string]$CharacterSet = 'Unicode',
        [ValidateRange(1, 100)][int]$MaxDepth = 12
    )
    process {
        foreach ($line in @(Format-PoshUITree @PSBoundParameters)) { Write-PoshUIHost $line }
    }
}

Export-ModuleMember -Function @('Format-PoshUITree', 'Show-PoshUITree')
