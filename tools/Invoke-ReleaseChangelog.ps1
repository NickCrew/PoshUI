#Requires -Version 7.6

<#
.SYNOPSIS
    Prepares or verifies a versioned release changelog

.DESCRIPTION
    Prepare moves curated Unreleased content into a dated version section. If
    Unreleased is empty, it generates notes from releasable Conventional Commits
    since the previous tag. Verify requires the tag, PowerShell manifest version,
    and changelog section to agree, and can write the exact section body to a file
    for GitHub release metadata.

    The script never creates a commit, tag, or publication.

.PARAMETER Action
    Preflight validates and renders without writing. Prepare updates
    CHANGELOG.md. Verify validates release agreement.

.PARAMETER Version
    Three-part release version required by Prepare, without a leading v.

.PARAMETER SinceTag
    Previous semantic release tag used for generated notes and compare links.

.PARAMETER Tag
    Semantic release tag required by Verify, including the leading v.

.PARAMETER ManifestPath
    PowerShell data manifest whose ModuleVersion must match Tag during Verify.

.PARAMETER OutputPath
    Optional UTF-8 file receiving the exact version-section notes during Verify.

.PARAMETER ReleaseDate
    Date written by Prepare. Defaults to today and exists to make behavior tests deterministic.

.INPUTS
    None.

.OUTPUTS
    None.

.EXAMPLE
    PS> ./tools/Invoke-ReleaseChangelog.ps1 -Action Prepare -Version 2.2.0 -SinceTag v2.1.1

    Rolls curated or generated notes into the 2.2.0 section.

.EXAMPLE
    PS> ./tools/Invoke-ReleaseChangelog.ps1 -Action Verify -Tag v2.2.0 -ManifestPath ./powershell/PoshUI.psd1

    Verifies the tag, manifest, and changelog agree.

.EXAMPLE
    PS> ./tools/Invoke-ReleaseChangelog.ps1 -Action Verify -Tag v2.2.0 -ManifestPath ./powershell/PoshUI.psd1 -OutputPath ./.release/notes.md

    Verifies the release and writes its notes for GitHub release metadata.

.NOTES
    Generated fallback notes contain only feat, fix, perf, revert, and breaking commits.

.LINK
    https://keepachangelog.com/en/1.1.0/
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Preflight', 'Prepare', 'Verify')]
    [string]$Action,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [ValidatePattern('^v\d+\.\d+\.\d+$')][string]$SinceTag,
    [ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Tag,
    [string]$ManifestPath,
    [string]$OutputPath,
    [datetime]$ReleaseDate = (Get-Date)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ChangelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
$Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-ChangelogSection {
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Name)

    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Content, "(?ms)^## \[$escaped\](?: - [^\r\n]+)?\r?\n(?<body>.*?)(?=^## \[|^\[[^\]]+\]:|\z)")
    if (-not $match.Success) { throw "CHANGELOG.md does not contain a [$Name] section." }
    return $match.Groups['body'].Value.Trim()
}

function Get-GeneratedReleaseNote {
    param([Parameter(Mandatory)][string]$BaselineTag)

    $raw = (& git -C $RepoRoot log --reverse --no-merges '--format=%H%x1f%s%x1f%b%x1e' "$BaselineTag..HEAD") -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "git log from $BaselineTag failed with exit $LASTEXITCODE." }
    $bullet = [Collections.Generic.List[string]]::new()
    foreach ($chunk in ($raw -split "`u{001e}")) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        $field = $chunk.TrimStart("`n") -split "`u{001f}"
        if ($field.Count -lt 2) { continue }
        $subject = $field[1]
        $body = if ($field.Count -ge 3) { $field[2] } else { '' }
        $breaking = $subject -match '^[a-z]+(?:\([^)]*\))?!:\s+.+' -or
            $body -match '(?m)^BREAKING[ -]CHANGE:'
        $match = [regex]::Match($subject, '^(?<type>feat|fix|perf|revert)(?:\((?<scope>[^)]*)\))?:\s+.+')
        $excludedScope = @('ci', 'docs', 'test', 'build', 'release', 'tooling')
        $releasable = $breaking -or ($match.Success -and $excludedScope -notcontains $match.Groups['scope'].Value)
        if ($releasable) { $bullet.Add("- $subject ($($field[0].Substring(0, 8)))") }
    }
    if ($bullet.Count -eq 0) { throw 'Unreleased is empty and no releasable Conventional Commits can provide fallback notes.' }
    return "### Changed`n`n" + ($bullet -join "`n")
}

if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) { throw "CHANGELOG.md was not found at $ChangelogPath." }
$content = [IO.File]::ReadAllText($ChangelogPath)

if ($Action -in @('Preflight', 'Prepare')) {
    if ([string]::IsNullOrWhiteSpace($Version)) { throw "-Version is required for $Action." }
    if ([string]::IsNullOrWhiteSpace($SinceTag)) { throw "-SinceTag is required for $Action." }
    if ($content -match "(?m)^## \[$([regex]::Escape($Version))\](?:\s|$)") { throw "CHANGELOG.md already contains a [$Version] section." }

    $notes = Get-ChangelogSection -Content $content -Name 'Unreleased'
    $meaningful = [regex]::Replace($notes, '(?s)<!--.*?-->', '').Trim()
    if ([string]::IsNullOrWhiteSpace($meaningful)) { $notes = Get-GeneratedReleaseNote -BaselineTag $SinceTag }

    $eol = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $bodyMatch = [regex]::Match($content, '(?ms)^## \[Unreleased\](?: - [^\r\n]+)?\r?\n.*?(?=^## \[|^\[[^\]]+\]:|\z)')
    if (-not $bodyMatch.Success) { throw 'CHANGELOG.md does not contain an Unreleased heading.' }
    $replacement = "## [Unreleased]$eol$eol## [$Version] - $($ReleaseDate.ToString('yyyy-MM-dd'))$eol$eol$($notes.Trim())$eol$eol"
    $updated = $content.Remove($bodyMatch.Index, $bodyMatch.Length).Insert($bodyMatch.Index, $replacement)

    $link = [regex]::Match($updated, '(?m)^\[Unreleased\]:\s+(?<prefix>.+?/compare/)v\d+\.\d+\.\d+\.\.\.HEAD\s*$')
    if ($link.Success) {
        $prefix = $link.Groups['prefix'].Value
        $newLinks = "[Unreleased]: ${prefix}v$Version...HEAD$eol[$Version]: $prefix$SinceTag...v$Version"
        $updated = $updated.Remove($link.Index, $link.Length).Insert($link.Index, $newLinks)
    }
    if ($Action -eq 'Preflight') {
        Write-Information "Validated CHANGELOG.md preparation for $Version." -InformationAction Continue
        return
    }

    [IO.File]::WriteAllText($ChangelogPath, $updated, $Utf8NoBom)
    Write-Information "Prepared CHANGELOG.md for $Version." -InformationAction Continue
    return
}

if ([string]::IsNullOrWhiteSpace($Tag)) { throw '-Tag is required for Verify.' }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { throw '-ManifestPath is required for Verify.' }
$resolvedManifest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ManifestPath)
$manifestVersion = (Import-PowerShellDataFile -Path $resolvedManifest).ModuleVersion
if ($Tag -ne "v$manifestVersion") { throw "Tag $Tag does not match the manifest ($manifestVersion)." }
$heading = [regex]::Match(
    $content,
    "(?m)^## \[$([regex]::Escape($manifestVersion))\] - (?<date>\d{4}-\d{2}-\d{2})\s*$"
)
if (-not $heading.Success) {
    throw "CHANGELOG.md section [$manifestVersion] must use a dated heading: ## [$manifestVersion] - YYYY-MM-DD."
}
$parsedDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact(
        $heading.Groups['date'].Value,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )) {
    throw "CHANGELOG.md section [$manifestVersion] does not contain a real calendar date."
}
$notes = Get-ChangelogSection -Content $content -Name $manifestVersion
$meaningfulNotes = [regex]::Replace($notes, '(?s)<!--.*?-->', '')
$meaningfulNotes = [regex]::Replace($meaningfulNotes, '(?m)^\s*#{1,6}\s+.*$', '').Trim()
if ([string]::IsNullOrWhiteSpace($meaningfulNotes) -or
    $meaningfulNotes -match '(?i)^(?:[-*]\s*)?(?:tbd|todo|n/?a|none|no changes|coming soon)\.?$') {
    throw "CHANGELOG.md section [$manifestVersion] has empty or placeholder release notes."
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    [IO.File]::WriteAllText($resolvedOutput, $notes.Trim() + "`n", $Utf8NoBom)
}
Write-Information "Verified $Tag against the manifest and CHANGELOG.md." -InformationAction Continue
