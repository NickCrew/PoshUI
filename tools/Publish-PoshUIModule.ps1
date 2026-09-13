#Requires -Version 7.6

<#
.SYNOPSIS
    Publishes the PoshUI PowerShell module to the Unanet Artifactory feed.

.DESCRIPTION
    Packs the runtime-only PowerShell module and pushes it to Artifactory's NuGet feed, so
    consumers can run Install-PSResource PoshUI instead of cloning this
    repository.

    The version comes from the manifest, and tools/Set-Version.ps1 -Check proves
    every other version site agrees with it, so the package version and the tag
    cannot drift apart.

    In CI the defaults resolve to the shared feed and the group-level JFrog
    credential, so the publish job passes no arguments.

.PARAMETER FeedUri
    NuGet v3 service index. Defaults to nuget-local, the local repository that
    backs the virtual nuget feed consumers read from.

.PARAMETER LookupUri
    Consumer-facing NuGet v3 service index used to discover package metadata.
    Defaults to the virtual nuget repository, which advertises the
    PackageBaseAddress resource needed for duplicate-version checks.

.PARAMETER Token
    Password half of the Basic credential. Defaults to JFROG_API_KEY.

.PARAMETER UserName
    Username half. Artifactory checks the username and key as a pair, so one is
    required. Defaults to JFROG_USER, then JFROG_USERNAME. In CI that is
    unanet-ci-rw, set alongside the job in .gitlab-ci.yml.

.PARAMETER ModulePath
    Directory holding the manifest. Defaults to powershell/ beside this script.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Progress goes to the information stream.

.EXAMPLE
    PS> ./tools/Publish-PoshUIModule.ps1

    Publishes to nuget-local using the JFrog credential in the environment.

.EXAMPLE
    PS> ./tools/Publish-PoshUIModule.ps1 -UserName me -Token $key -WhatIf

    Reports what would be published without pushing anything.

.NOTES
    Authentication is Basic, supplied as a PSCredential, because Artifactory
    authenticates the username and key together rather than the key alone.

    The push targets nuget-local rather than the virtual nuget feed, which has
    no default deployment repository configured. Artifactory serves a v3 index
    whose PackagePublish resource points back at its v2 endpoint, and that is
    where PSResourceGet posts the package.

    -ApiVersion V3 pins the protocol. PSResourceGet also probes it correctly
    from an index.json URI, but the probe is a URI-shape heuristic and this is
    the release path.

.LINK
    https://gitlab.unanet.io/cosential/dev-tools/posh-ui
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'The token arrives as a CI variable and PSCredential is the only shape Publish-PSResource accepts. It never leaves this process.'
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FeedUri = "https://unanet.jfrog.io/artifactory/api/nuget/v3/nuget-local/index.json",
    [string]$LookupUri = "https://unanet.jfrog.io/artifactory/api/nuget/v3/nuget/index.json",
    [string]$Token,
    [string]$UserName,
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
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )

    $findErrors = @()
    $resources = @(
        Find-PSResource `
            -Name $PackageName `
            -Version $Version `
            -Repository $RepositoryName `
            -Credential $Credential `
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
        throw "The consumer repository returned more than one PoshUI $Version package."
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
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )

    $temporaryRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) "tmp/posh-ui-publish-$([guid]::NewGuid().ToString('N'))"
    $expandedPath = Join-Path $temporaryRoot 'published'

    try {
        New-Item -ItemType Directory -Path $expandedPath -Force | Out-Null
        Save-PSResource `
            -Name $PackageName `
            -Version $Version `
            -Repository $RepositoryName `
            -Credential $Credential `
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

if (-not $UserName) { $UserName = $env:JFROG_USER }
if (-not $UserName) { $UserName = $env:JFROG_USERNAME }
if (-not $UserName) {
    throw "No -UserName given and neither JFROG_USER nor JFROG_USERNAME is set, so the publish cannot authenticate."
}

if (-not $Token) {
    $Token = $env:JFROG_API_KEY
    if (-not $Token) {
        throw "No -Token given and JFROG_API_KEY is not set, so the publish cannot authenticate."
    }
}

$version = (Import-PowerShellDataFile -Path (Join-Path $ModulePath "PoshUI.psd1")).ModuleVersion
Write-Verbose "Publishing PoshUI $version from $ModulePath"

# A name local to this run. Registering is machine state, so it is removed in
# finally whether or not the push succeeds.
$repositoryName = "posh-ui-publish-$PID"
$lookupRepositoryName = "posh-ui-lookup-$PID"

if (-not $PSCmdlet.ShouldProcess($FeedUri, "Publish PoshUI $version")) { return }

$packageStage = New-PoshUIPackageStage -SourcePath $ModulePath
try {
    Register-PSResourceRepository -Name $repositoryName -Uri $FeedUri -ApiVersion V3 -Trusted -Force
    Register-PSResourceRepository -Name $lookupRepositoryName -Uri $LookupUri -ApiVersion V3 -Trusted -Force
    $credential = [PSCredential]::new(
        $UserName,
        (ConvertTo-SecureString $Token -AsPlainText -Force))

    $status = Get-PoshUIPackageStatus -RepositoryName $lookupRepositoryName -PackageName 'PoshUI' -Version $version -Credential $credential
    if ($status.Published) {
        if (Test-PoshUIPublishedPayloadMatch -RepositoryName $lookupRepositoryName -PackageName 'PoshUI' -Version $version -SourcePath $packageStage -Credential $credential) {
            Write-Information "PoshUI $version is already published with the exact expected payload." -InformationAction Continue
            return
        }
        throw "PoshUI $version is already published to $FeedUri with different package content. Refusing to overwrite it."
    }

    Publish-PSResource -Path $packageStage -Repository $repositoryName -Credential $credential -SkipDependenciesCheck
    Write-Information "Published PoshUI $version to $FeedUri" -InformationAction Continue
}
finally {
    Unregister-PSResourceRepository -Name $repositoryName -ErrorAction SilentlyContinue
    Unregister-PSResourceRepository -Name $lookupRepositoryName -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $packageStage -Recurse -Force -ErrorAction SilentlyContinue
}
