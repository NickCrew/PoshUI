#Requires -Version 7.6

<#
.SYNOPSIS
    Derives the next semantic version from the Conventional Commits since the last release tag.

.DESCRIPTION
    Reads the commits between the most recent v* tag and HEAD, classifies each by
    its Conventional Commits type, and reports the version those commits imply. A
    breaking change bumps major, a feat bumps minor, a fix, perf, or revert bumps
    patch, and everything else releases nothing.

    With -Apply it hands the result to tools/Set-Version.ps1, then rolls curated
    Unreleased notes into a dated CHANGELOG.md section. Releasable Conventional
    Commits provide fallback notes when Unreleased is empty.

    Before the first v* tag exists there is nothing to measure from, so the
    version currently in the manifest is used as the baseline.

.PARAMETER SinceTag
    Release tag to measure from. Defaults to the highest v* tag reachable from
    HEAD, or the manifest version when the repository has no v* tag yet.

.PARAMETER Apply
    Write the derived version through tools/Set-Version.ps1 and prepare its
    CHANGELOG.md section.

.PARAMETER AsObject
    Emit the version together with the commits that decided it.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.String

    The derived version, or nothing when no commit warrants a release.

.EXAMPLE
    PS> ./tools/Get-NextVersion.ps1
    2.1.0

.EXAMPLE
    PS> ./tools/Get-NextVersion.ps1 -Apply

    Stamps the derived version and prepares its changelog section.

.NOTES
    The derivation is only as accurate as the commit subjects. A change that
    breaks callers but is committed as a plain feat reads as a minor here, so
    the ! marker and the BREAKING CHANGE footer are load-bearing.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SinceTag,

    [switch]$Apply,

    [switch]$AsObject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "powershell/PoshUI.psd1"

# type(scope)!: subject. The scope and the bang are both optional.
$SubjectPattern = '^(?<type>[a-z]+)(?:\((?<scope>[^)]*)\))?(?<bang>!)?:\s+(?<subject>.+)$'

# conventionalcommits maps these to a patch. Every other type releases nothing.
$PatchType = @("fix", "perf", "revert")
$ReleaseExcludedScope = @('ci', 'docs', 'test', 'build', 'release', 'tooling')

$BumpRank = @{ none = 0; patch = 1; minor = 2; major = 3 }

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Argument)

    $output = & git -C $RepoRoot @Argument
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Argument -join ' ') failed with exit $LASTEXITCODE"
    }
    return $output
}

function Get-ReleaseTag {
    # -v:refname sorts by version rather than lexically, which is the difference
    # between v2.2.0 and v2.10.0 comparing correctly. --merged so a tag on an
    # unrelated branch cannot become the baseline.
    $tag = Invoke-Git -Argument @("tag", "--list", "v[0-9]*", "--sort=-v:refname", "--merged", "HEAD")
    if (-not $tag) { return $null }
    return @($tag)[0]
}

function Get-CommitRecord {
    param([AllowNull()][string]$Tag)

    $range = if ($Tag) { "$Tag..HEAD" } else { "HEAD" }

    # Unit separator between fields and record separator between commits, so a
    # multi-line body cannot be mistaken for the next commit.
    $raw = (Invoke-Git -Argument @("log", "--no-merges", "--format=%H%x1f%s%x1f%b%x1e", $range)) -join "`n"

    $record = @()
    foreach ($chunk in ($raw -split "`u{001e}")) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        $field = $chunk.TrimStart("`n") -split "`u{001f}"
        if ($field.Count -lt 2) { continue }
        $record += [PSCustomObject]@{
            Hash    = $field[0]
            Subject = $field[1]
            Body    = if ($field.Count -ge 3) { $field[2] } else { "" }
        }
    }
    return $record
}

function Get-CommitBump {
    param(
        [Parameter(Mandatory = $true)][string]$Subject,
        [AllowEmptyString()][string]$Body
    )

    # A BREAKING CHANGE footer outranks the subject line, and the hyphenated
    # spelling is equally valid per the specification.
    if ($Body -match '(?m)^BREAKING[ -]CHANGE:') { return "major" }
    if ($Subject -notmatch $SubjectPattern) { return "none" }
    if ($Matches["bang"]) { return "major" }
    if ($ReleaseExcludedScope -contains $Matches['scope']) { return 'none' }
    if ($Matches["type"] -eq "feat") { return "minor" }
    if ($PatchType -contains $Matches["type"]) { return "patch" }
    return "none"
}

$baseline = $null
$tag = if ($SinceTag) { $SinceTag } else { Get-ReleaseTag }

if ($tag) {
    $baseline = $tag -replace '^v', ""
    Write-Verbose "Measuring from $tag"
}
else {
    # No release has been tagged yet, so the manifest is the only statement of
    # where the version currently stands.
    $baseline = (Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
    Write-Verbose "No v* tag yet, using the manifest as the baseline: $baseline"
}

$commit = @(Get-CommitRecord -Tag $tag)
if ($commit.Count -eq 0) {
    Write-Verbose "No commits since $tag."
    return
}

$analysis = foreach ($c in $commit) {
    [PSCustomObject]@{
        Hash    = $c.Hash.Substring(0, 8)
        Subject = $c.Subject
        Bump    = Get-CommitBump -Subject $c.Subject -Body $c.Body
    }
}

$winning = "none"
foreach ($a in $analysis) {
    if ($BumpRank[$a.Bump] -gt $BumpRank[$winning]) { $winning = $a.Bump }
}

if ($winning -eq "none") {
    Write-Verbose "$($commit.Count) commit(s) since $baseline, none of a releasable type."
    return
}

$part = $baseline -split '\.'
if ($part.Count -lt 3) {
    throw "Baseline $baseline is not a three-part version, so the next one cannot be derived from it."
}
[int]$major = $part[0]
[int]$minor = $part[1]
[int]$patch = $part[2]

switch ($winning) {
    "major" { $major++; $minor = 0; $patch = 0 }
    "minor" { $minor++; $patch = 0 }
    "patch" { $patch++ }
}
$next = "$major.$minor.$patch"
Write-Verbose "$($commit.Count) commit(s) since $baseline imply a $winning bump: $next"

if ($Apply) {
    if ($PSCmdlet.ShouldProcess('release metadata', "Set version and changelog to $next")) {
        # Before the first v* tag exists, $tag is null. Invoke-ReleaseChangelog.ps1
        # requires -SinceTag to match a vX.Y.Z tag, and the manifest baseline
        # already satisfies that shape, so it stands in as the changelog's
        # "since" reference until a real tag exists.
        $changelogSinceTag = if ($tag) { $tag } else { "v$baseline" }
        & (Join-Path $PSScriptRoot 'Invoke-ReleaseChangelog.ps1') `
            -Action Preflight `
            -Version $next `
            -SinceTag $changelogSinceTag

        & (Join-Path $PSScriptRoot "Set-Version.ps1") -Version $next
        & (Join-Path $PSScriptRoot 'Invoke-ReleaseChangelog.ps1') `
            -Action Prepare `
            -Version $next `
            -SinceTag $changelogSinceTag
    }
}

if ($AsObject) {
    [PSCustomObject]@{
        Version  = $next
        Bump     = $winning
        Baseline = $baseline
        SinceTag = $tag
        Commit   = $analysis
    }
}
else {
    $next
}
