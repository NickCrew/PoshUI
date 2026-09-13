#Requires -Version 7.6

<#
.SYNOPSIS
    Writes the framework version into every file that states it.

.DESCRIPTION
    The version is authored in one place, ModuleVersion in
    powershell/PoshUI.psd1, and restated in both implementations' entry
    points, CLIs, installers, and banners. Those restatements are generated:
    this script writes them, and -Check proves they still agree.

    PoshUI cannot do what a single-language module does and read the version
    both sides lives in quoted here-strings that deliberately contain literal
    $POSH_UI_HOME, so making them interpolate would expand more than the
    version. Stamping and then checking is the honest alternative to a runtime
    lookup that only half the repository can perform.

    The demo applications' own versions (APP_VERSION, $script:AppVersion) are
    deliberately absent below. Those belong to the fictional app the dashboard
    renders, not to the framework, and they are the same number today only by
    coincidence.

.PARAMETER Version
    Version to write. Defaults to ModuleVersion in the manifest, which makes a
    bare run re-stamp every generated site from the authored one.

.PARAMETER Check
    Report sites that disagree and exit non-zero without writing anything.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Findings go to the information stream.

.EXAMPLE
    PS> ./tools/Set-Version.ps1 -Check

    Fails if any generated site disagrees with the manifest.

.EXAMPLE
    PS> ./tools/Set-Version.ps1 -Version 2.1.0

    Writes 2.1.0 to the manifest and every site generated from it.

.NOTES
    Box-drawing banners are padded to a fixed width. A longer version would push
    the closing bar out of alignment, so a replacement inside a bordered line has
    its trailing run of spaces adjusted to hold the original width.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'A maintainer-facing script whose console output is the result. Nothing consumes it as data.'
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Version,

    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "powershell/PoshUI.psd1"

# Each entry names a file and a pattern with three groups: what precedes the
# version, the version, and what follows. Every pattern is anchored to the
# statement that carries it rather than matching a bare number, so an unrelated
# 2.0.0 elsewhere in a file is never touched.
$VersionSite = @(
    @{ Path = "powershell/PoshUI.psd1"; Pattern = "(?m)^(?<pre>\s*ModuleVersion\s*=\s*')(?<v>[^']+)(?<post>')" }
    @{ Path = "README.md"; Pattern = "(?<pre>img\.shields\.io/badge/version-)(?<v>\d+\.\d+\.\d+)(?<post>-)" }
    @{ Path = "README.md"; Pattern = '(?<pre>alt="Version )(?<v>\d+\.\d+\.\d+)(?<post>")' }
)

# A bordered line is padded to a fixed width, so a version that changes length
# has to give the difference back to the run of spaces before the closing bar.
function Repair-BorderWidth {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][int]$Width
    )

    $bar = [char]0x2551
    if (-not $Line.EndsWith($bar)) { return $Line }

    $delta = $Width - $Line.Length
    if ($delta -eq 0) { return $Line }

    $body = $Line.Substring(0, $Line.Length - 1)
    if ($delta -gt 0) { return $body + (" " * $delta) + $bar }

    $trimmed = $body.TrimEnd(" ")
    $removable = $body.Length - $trimmed.Length
    if ($removable -lt -$delta) {
        throw "Cannot narrow a bordered line in place: '$Line'"
    }
    return $body.Substring(0, $body.Length + $delta) + $bar
}

if (-not $Version) {
    $Version = (Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
    Write-Verbose "No -Version given, re-stamping from the manifest: $Version"
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version '$Version' is not a three-part version."
}

$disagreement = @()
$written = @()

foreach ($site in $VersionSite) {
    $path = Join-Path $RepoRoot $site.Path
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Version site missing: $($site.Path)"
    }

    $content = Get-Content -LiteralPath $path -Raw
    $match = [regex]::Matches($content, $site.Pattern)
    if ($match.Count -eq 0) {
        throw "Pattern matched nothing in $($site.Path): $($site.Pattern)"
    }

    $updated = [regex]::Replace($content, $site.Pattern, {
            param($m)
            $m.Groups["pre"].Value + $Version + $m.Groups["post"].Value
        })

    if ($updated -eq $content) { continue }

    # Restore any bordered line this widened or narrowed.
    $eol = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $originalLine = $content -split "`r?`n"
    $updatedLine = $updated -split "`r?`n"
    for ($i = 0; $i -lt $updatedLine.Count; $i++) {
        if ($i -lt $originalLine.Count -and $updatedLine[$i] -ne $originalLine[$i]) {
            $updatedLine[$i] = Repair-BorderWidth -Line $updatedLine[$i] -Width $originalLine[$i].Length
        }
    }
    $updated = $updatedLine -join $eol

    foreach ($m in $match) {
        if ($m.Groups["v"].Value -ne $Version) {
            $disagreement += "$($site.Path): $($m.Groups['v'].Value)"
        }
    }

    if ($Check) { continue }

    if ($PSCmdlet.ShouldProcess($site.Path, "Set version to $Version")) {
        Set-Content -LiteralPath $path -Value $updated -NoNewline
        $written += $site.Path
    }
}

if ($Check) {
    if ($disagreement.Count -gt 0) {
        Write-Host "Version sites disagree with $Version" -ForegroundColor Red
        $disagreement | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Run ./tools/Set-Version.ps1 to re-stamp them."
        exit 1
    }
    Write-Host "All $($VersionSite.Count) version sites agree with $Version."
    return
}

if ($written.Count -eq 0) {
    Write-Host "All $($VersionSite.Count) version sites already read $Version."
}
else {
    Write-Host "Stamped $Version into $(($written | Sort-Object -Unique).Count) file(s):"
    $written | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
}

if (-not $Check) {
    $documentationGenerator = Join-Path $PSScriptRoot 'Update-Docs.ps1'
    if (Test-Path -LiteralPath $documentationGenerator -PathType Leaf) {
        & $documentationGenerator
    }
}
