#Requires -Version 7.6
#Requires -Modules Microsoft.PowerShell.PSResourceGet

<#
.SYNOPSIS
    Registers the shared Unanet package feed and installs PoshUI

.DESCRIPTION
    Registers Unanet's Artifactory NuGet v3 feed with PSResourceGet, resolves a
    JFrog credential from the current machine, and installs PoshUI for the
    current user.

    The key comes from -Token, then JFROG_API_KEY. The username comes from
    -UserName, JFROG_USER, then JFROG_USERNAME. Artifactory authenticates the
    two halves together and nothing can derive the username from the key, so
    both have to be present. The dev-stack setup instructions already put
    JFROG_USERNAME and JFROG_API_KEY in a developer environment, which is why
    this usually runs with no arguments.

    The credential is used for this install only. It is not persisted in the
    repository registration, so later Find-PSResource and Update-PSResource
    commands still need -Credential.

.PARAMETER Name
    PSResourceGet repository name. Defaults to unanet-nuget.

.PARAMETER FeedUri
    NuGet v3 service index. Defaults to the virtual nuget feed, which serves
    every package published to Artifactory.

.PARAMETER Credential
    Basic credential for the feed. Takes precedence over -UserName, -Token, and
    the supported environment variables.

.PARAMETER UserName
    JFrog username, usually your full email address. Defaults to JFROG_USER,
    then JFROG_USERNAME.

.PARAMETER Token
    JFrog identity token. Defaults to JFROG_API_KEY.

.PARAMETER RegisterOnly
    Registers the repository without resolving a credential or installing
    PoshUI.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Progress goes to the information stream.

.EXAMPLE
    PS> ./powershell/tools/Register-UnanetFeed.ps1

    Registers the feed and installs PoshUI using the first supported credential
    found in the environment.

.EXAMPLE
    PS> ./powershell/tools/Register-UnanetFeed.ps1 -UserName reader -Token $token

    Installs with an explicit JFrog username and identity token.

.EXAMPLE
    PS> ./powershell/tools/Register-UnanetFeed.ps1 -RegisterOnly

    Registers the feed without resolving a credential or installing PoshUI.

.NOTES
    Requires PowerShell 7.6 and Microsoft.PowerShell.PSResourceGet. -ApiVersion V3
    pins the protocol rather than leaving PSResourceGet to infer it from the URI.

    The feed answers anonymous reads with 401, so a run with no credential fails
    on the first request instead of quietly resolving PoshUI somewhere else.

.LINK
    https://gitlab.unanet.io/cosential/dev-tools/dev-stack

.LINK
    https://unanet.jfrog.io/ui/user_profile

.LINK
    https://jfrog.com/help/r/jfrog-artifactory-documentation/nuget-repositories

.LINK
    Register-PSResourceRepository

.LINK
    Install-PSResource
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'The token arrives as a parameter or environment variable, and PSCredential is the only shape PSResourceGet accepts. It never leaves this process.'
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'unanet-nuget',

    [string]$FeedUri = 'https://unanet.jfrog.io/artifactory/api/nuget/v3/nuget/index.json',

    [PSCredential]$Credential,

    [string]$UserName,

    [string]$Token,

    [switch]$RegisterOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PoshUIFeedCredential {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'See the script-level suppression. The token is already plaintext when it reaches this function.'
    )]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [PSCredential]$Credential,

        [string]$UserName,

        [string]$Token
    )

    if ($Credential) { return $Credential }

    if (-not $Token) { $Token = $env:JFROG_API_KEY }
    if (-not $Token) { return $null }

    if (-not $UserName) { $UserName = $env:JFROG_USER }
    if (-not $UserName) { $UserName = $env:JFROG_USERNAME }

    if (-not $UserName) {
        throw 'Found a token but no username to pair it with, and Artifactory authenticates both. Pass -UserName or set JFROG_USER.'
    }

    return [PSCredential]::new(
        $UserName,
        (ConvertTo-SecureString $Token -AsPlainText -Force))
}

if ($PSCmdlet.ShouldProcess($FeedUri, "Register PSResource repository '$Name'")) {
    Register-PSResourceRepository -Name $Name -Uri $FeedUri -ApiVersion V3 -Trusted -Force
    Write-Information "Registered '$Name' at $FeedUri" -InformationAction Continue
}

if ($RegisterOnly) { return }

if ($PSCmdlet.ShouldProcess('PoshUI', "Install from '$Name'")) {
    $feedCredential = Resolve-PoshUIFeedCredential `
        -Credential $Credential `
        -UserName $UserName `
        -Token $Token

    if (-not $feedCredential) {
        throw 'No feed token found. Pass -Credential or -Token, or set JFROG_API_KEY as the dev-stack setup describes.'
    }

    Install-PSResource `
        -Name PoshUI `
        -Repository $Name `
        -Credential $feedCredential `
        -Scope CurrentUser `
        -TrustRepository

    $installed = Get-InstalledPSResource -Name PoshUI -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($installed) {
        Write-Information "Installed PoshUI $($installed.Version). Run Import-Module PoshUI to use it." -InformationAction Continue
    }
}
