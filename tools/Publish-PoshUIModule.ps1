#Requires -Version 7.6

<#
.SYNOPSIS
    Publishes the PoshUI PowerShell module to the PowerShell Gallery

.DESCRIPTION
    Packs the runtime-only PowerShell module and pushes it to the PowerShell
    Gallery, so consumers can run Install-PSResource PoshUI instead of cloning
    this repository.

    The version comes from the manifest, and tools/Set-Version.ps1 -Check
    proves every other version site agrees with it, so the package version and
    the tag cannot drift apart.

    In CI the API key comes from the PSGALLERY_API_KEY secret, so the publish
    job passes no arguments.

.PARAMETER ApiKey
    PowerShell Gallery API key. Defaults to PSGALLERY_API_KEY.

.PARAMETER ModulePath
    Directory holding the manifest. Defaults to powershell/ beside this script.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Progress goes to the information stream.

.EXAMPLE
    PS> ./tools/Publish-PoshUIModule.ps1

    Publishes to the PowerShell Gallery using PSGALLERY_API_KEY from the environment.

.EXAMPLE
    PS> ./tools/Publish-PoshUIModule.ps1 -ApiKey $key -WhatIf

    Reports what would be published without pushing anything.

.NOTES
    The PowerShell Gallery is a single public repository, so this script does
    not register or credential a private feed. The publish endpoint accepts a
    single API key rather than a username and key pair.

.LINK
    https://github.com/NickCrew/PoshUI
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ApiKey,
    [string]$ModulePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ModulePath) { $ModulePath = Join-Path $RepoRoot "powershell" }

function Get-PoshUIPackageStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $findErrors = @()
    $resources = @(
        Find-PSResource `
            -Name $PackageName `
            -Version $Version `
            -Repository PSGallery `
            -ErrorAction SilentlyContinue `
            -ErrorVariable +findErrors
    )
    $unexpectedErrors = @(
        $findErrors | Where-Object {
            $_.FullyQualifiedErrorId -notlike 'PackageNotFound,*'
        }
    )
    if ($unexpectedErrors.Count -gt 0) {
        throw $unexpectedErrors[0]
    }
    if ($resources.Count -gt 1) {
        throw "The PowerShell Gallery returned more than one PoshUI $Version package."
    }

    return [PSCustomObject]@{
        Published = $resources.Count -eq 1
        Resource  = $resources | Select-Object -First 1
    }
}

function Get-PoshUIPayloadManifest {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [switch]$Packed
    )

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $excluded = @('_rels/', 'package/', '[Content_Types].xml', 'PoshUI.nuspec')
    return @(
        Get-ChildItem -LiteralPath $rootPath -File -Recurse |
            ForEach-Object {
                $relative = $_.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
                if ($Packed -and ($excluded | Where-Object {
                            $relative -eq $_ -or $relative.StartsWith($_, [StringComparison]::Ordinal)
                        })) {
                    return
                }
                '{0} {1}' -f $relative, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } |
            Sort-Object
    )
}

function New-PoshUIPackageStage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private staging helper owned by the parent ShouldProcess operation.')]
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$SourcePath)

    $temporaryRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) "tmp/posh-ui-package-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    foreach ($entry in @('PoshUI.psd1', 'PoshUI.psm1', 'README.md', 'modules')) {
        $source = Join-Path $SourcePath $entry
        if (-not (Test-Path -LiteralPath $source)) { throw "Package payload entry is missing: $entry" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $temporaryRoot $entry) -Recurse -Force
    }
    $temporaryRoot
}

function Test-PoshUIPublishedPayloadMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $temporaryRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) "tmp/posh-ui-publish-$([guid]::NewGuid().ToString('N'))"
    $expandedPath = Join-Path $temporaryRoot 'published'

    try {
        New-Item -ItemType Directory -Path $expandedPath -Force | Out-Null
        Save-PSResource `
            -Name $PackageName `
            -Version $Version `
            -Repository PSGallery `
            -Path $temporaryRoot `
            -AsNupkg `
            -TrustRepository `
            -SkipDependencyCheck
        $packages = @(Get-ChildItem -LiteralPath $temporaryRoot -Filter '*.nupkg' -File)
        if ($packages.Count -ne 1) {
            throw "Expected one downloaded PoshUI $Version package, found $($packages.Count)."
        }
        $packagePath = $packages[0].FullName
        Expand-Archive -LiteralPath $packagePath -DestinationPath $expandedPath -Force
        $sourceManifest = @(Get-PoshUIPayloadManifest -Root $SourcePath)
        $publishedManifest = @(Get-PoshUIPayloadManifest -Root $expandedPath -Packed)
        return $null -eq (Compare-Object -ReferenceObject $sourceManifest -DifferenceObject $publishedManifest)
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $ApiKey) { $ApiKey = $env:PSGALLERY_API_KEY }
if (-not $ApiKey) {
    throw "No -ApiKey given and PSGALLERY_API_KEY is not set, so the publish cannot authenticate."
}

$version = (Import-PowerShellDataFile -Path (Join-Path $ModulePath "PoshUI.psd1")).ModuleVersion
Write-Verbose "Publishing PoshUI $version from $ModulePath"

if (-not $PSCmdlet.ShouldProcess('PSGallery', "Publish PoshUI $version")) { return }

$packageStage = New-PoshUIPackageStage -SourcePath $ModulePath
try {
    $status = Get-PoshUIPackageStatus -PackageName 'PoshUI' -Version $version
    if ($status.Published) {
        if (Test-PoshUIPublishedPayloadMatch -PackageName 'PoshUI' -Version $version -SourcePath $packageStage) {
            Write-Information "PoshUI $version is already published with the exact expected payload." -InformationAction Continue
            return
        }
        throw "PoshUI $version is already published to the PowerShell Gallery with different package content. Refusing to overwrite it."
    }

    Publish-PSResource -Path $packageStage -Repository PSGallery -ApiKey $ApiKey -SkipDependenciesCheck
    Write-Information "Published PoshUI $version to the PowerShell Gallery" -InformationAction Continue
}
finally {
    Remove-Item -LiteralPath $packageStage -Recurse -Force -ErrorAction SilentlyContinue
}
