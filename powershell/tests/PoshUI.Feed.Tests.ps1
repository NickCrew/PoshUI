#Requires -Version 7.6

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Builds fake credentials from literal test values. No secret leaves the test process.'
)]
param()

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ScriptPath = Join-Path $script:ModuleRoot 'tools/Register-UnanetFeed.ps1'

    # A developer machine has these set, so clear them or the suite reports on
    # the machine rather than on the script.
    $script:SavedEnv = @{}
    foreach ($name in @(
            'JFROG_USER'
            'JFROG_USERNAME'
            'JFROG_API_KEY'
        )) {
        $script:SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }

    . $script:ScriptPath -WhatIf
}

AfterAll {
    foreach ($name in $script:SavedEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $script:SavedEnv[$name])
    }
}

Describe 'Feed credential resolution' {
    It 'passes an explicit credential through untouched' {
        $supplied = [PSCredential]::new(
            'someone',
            (ConvertTo-SecureString 'secret' -AsPlainText -Force))

        Resolve-PoshUIFeedCredential -Credential $supplied | Should -Be $supplied
    }

    It 'prefers an explicit credential over every other source' {
        $env:JFROG_API_KEY = 'ambient'
        $env:JFROG_USERNAME = 'ambient-user'
        $supplied = [PSCredential]::new(
            'supplied',
            (ConvertTo-SecureString 'secret' -AsPlainText -Force))
        try {
            $resolved = Resolve-PoshUIFeedCredential `
                -Credential $supplied `
                -UserName 'other' `
                -Token 'explicit'

            $resolved | Should -Be $supplied
        }
        finally {
            $env:JFROG_API_KEY = $null
            $env:JFROG_USERNAME = $null
        }
    }

    It 'builds a credential from an explicit username and token' {
        $resolved = Resolve-PoshUIFeedCredential -UserName 'reader' -Token 't'

        $resolved.UserName | Should -Be 'reader'
        $resolved.GetNetworkCredential().Password | Should -Be 't'
    }

    It 'reads JFROG_API_KEY when no token is passed' {
        $env:JFROG_API_KEY = 'from-env'
        try {
            $resolved = Resolve-PoshUIFeedCredential -UserName 'someone'
            $resolved.GetNetworkCredential().Password | Should -Be 'from-env'
        }
        finally { $env:JFROG_API_KEY = $null }
    }

    It 'does not let an ambient token override an explicit one' {
        $env:JFROG_API_KEY = 'ambient'
        try {
            $resolved = Resolve-PoshUIFeedCredential -UserName 'someone' -Token 'explicit'
            $resolved.GetNetworkCredential().Password | Should -Be 'explicit'
        }
        finally { $env:JFROG_API_KEY = $null }
    }

    It 'prefers JFROG_USER over JFROG_USERNAME' {
        $env:JFROG_USER = 'ci-user'
        $env:JFROG_USERNAME = 'personal-user'
        try {
            $resolved = Resolve-PoshUIFeedCredential -Token 't'
            $resolved.UserName | Should -Be 'ci-user'
        }
        finally {
            $env:JFROG_USER = $null
            $env:JFROG_USERNAME = $null
        }
    }

    It 'falls back to JFROG_USERNAME' {
        $env:JFROG_USERNAME = 'personal-user'
        try {
            $resolved = Resolve-PoshUIFeedCredential -Token 't'
            $resolved.UserName | Should -Be 'personal-user'
        }
        finally { $env:JFROG_USERNAME = $null }
    }

    It 'does not let an ambient username override an explicit one' {
        $env:JFROG_USER = 'ambient'
        try {
            $resolved = Resolve-PoshUIFeedCredential -UserName 'given' -Token 't'
            $resolved.UserName | Should -Be 'given'
        }
        finally { $env:JFROG_USER = $null }
    }

    It 'refuses to guess a username when none is available' {
        { Resolve-PoshUIFeedCredential -Token 't' } |
            Should -Throw '*no username to pair it with*'
    }

    It 'returns nothing when no token is available' {
        Resolve-PoshUIFeedCredential | Should -BeNullOrEmpty
    }
}

Describe 'Repository registration and installation' {
    BeforeEach {
        Mock Register-PSResourceRepository { }
        Mock Install-PSResource { }
        Mock Get-InstalledPSResource { }
        Mock Get-Credential { throw 'Get-Credential should not be reached in these tests.' }
        Mock Write-Information { }
    }

    It 'defaults to the shared Artifactory feed' {
        $FeedUri | Should -Be 'https://unanet.jfrog.io/artifactory/api/nuget/v3/nuget/index.json'
        $Name | Should -Be 'unanet-nuget'
    }

    It 'registers the repository as trusted NuGet v3' {
        . $script:ScriptPath -Name 'unit-test-feed' -RegisterOnly

        Should -Invoke Register-PSResourceRepository -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'unit-test-feed' -and
            $Uri -eq 'https://unanet.jfrog.io/artifactory/api/nuget/v3/nuget/index.json' -and
            $ApiVersion -eq 'V3' -and
            $Trusted.IsPresent -and
            $Force.IsPresent
        }
    }

    It 'stops after registration when requested' {
        . $script:ScriptPath -Name 'unit-test-feed' -RegisterOnly

        Should -Invoke Install-PSResource -Times 0 -Exactly
        Should -Invoke Get-Credential -Times 0 -Exactly
    }

    It 'installs PoshUI into the current user scope' {
        . $script:ScriptPath -Name 'unit-test-feed' -UserName 'u' -Token 't' -Confirm:$false

        Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PoshUI' -and
            $Repository -eq 'unit-test-feed' -and
            $Scope -eq 'CurrentUser' -and
            $TrustRepository.IsPresent -and
            $Credential.UserName -eq 'u'
        }
    }

    It 'fails immediately when no credential source is available' {
        { . $script:ScriptPath -Name 'unit-test-feed' -Confirm:$false } |
            Should -Throw '*No feed token found*'

        Should -Invoke Install-PSResource -Times 0 -Exactly
        Should -Invoke Get-Credential -Times 0 -Exactly
    }

    It 'neither registers, installs, nor prompts under WhatIf' {
        . $script:ScriptPath -Name 'unit-test-feed' -WhatIf

        Should -Invoke Register-PSResourceRepository -Times 0 -Exactly
        Should -Invoke Install-PSResource -Times 0 -Exactly
        Should -Invoke Get-Credential -Times 0 -Exactly
    }
}
