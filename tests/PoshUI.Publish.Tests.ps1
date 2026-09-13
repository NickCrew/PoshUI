#Requires -Version 7.6

BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:PublishScript = Join-Path $script:RepositoryRoot 'tools/Publish-PoshUIModule.ps1'
    $script:AutomaticReleaseScript = Join-Path $script:RepositoryRoot 'scripts/automatic_release.sh'
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'powershell/PoshUI.psd1'
    $script:ManifestVersion = (Import-PowerShellDataFile -Path $script:ManifestPath).ModuleVersion

    function Get-CiJobBlock {
        param(
            [Parameter(Mandatory)][string]$Content,
            [Parameter(Mandatory)][string]$Name
        )

        $escaped = [regex]::Escape($Name)
        return [regex]::Match(
            $Content,
            "(?ms)^${escaped}:\s*`$(.*?)(?=^[a-zA-Z][a-zA-Z0-9:-]*:\s*`$|\z)"
        ).Groups[1].Value
    }

    function New-PublishedPackageFixture {
        param(
            [Parameter(Mandatory)][string]$SourcePath,
            [Parameter(Mandatory)][string]$DestinationPath,
            [switch]$DifferentPayload
        )

        $staging = Join-Path (Split-Path -Parent $DestinationPath) ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        foreach ($entry in @('PoshUI.psd1', 'PoshUI.psm1', 'README.md', 'modules')) {
            Copy-Item -LiteralPath (Join-Path $SourcePath $entry) -Destination $staging -Recurse -Force
        }
        New-Item -ItemType Directory -Path (Join-Path $staging '_rels') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $staging 'package/services/metadata/core-properties') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staging '_rels/.rels') -Value '<Relationships />'
        Set-Content -LiteralPath (Join-Path $staging 'package/services/metadata/core-properties/package.psmdcp') -Value '<coreProperties />'
        Set-Content -LiteralPath (Join-Path $staging '[Content_Types].xml') -Value '<Types />'
        Set-Content -LiteralPath (Join-Path $staging 'PoshUI.nuspec') -Value '<package />'
        if ($DifferentPayload) {
            Add-Content -LiteralPath (Join-Path $staging 'PoshUI.psm1') -Value "`n# different published payload"
        }
        [IO.Compression.ZipFile]::CreateFromDirectory($staging, $DestinationPath)
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}

Describe 'Publish-PoshUIModule feed guard' {
    BeforeEach {
        $env:JFROG_API_KEY = $null
        $env:POSHUI_TEST_VERSION = $script:ManifestVersion
        $env:POSHUI_TEST_NUPKG = $null

        Mock Register-PSResourceRepository {}
        Mock Unregister-PSResourceRepository {}
        Mock Publish-PSResource {}
        Mock Find-PSResource {}
        Mock Save-PSResource {}
        Mock Write-Information {}
    }

    AfterEach {
        $env:JFROG_API_KEY = $null
        $env:POSHUI_TEST_VERSION = $null
        $env:POSHUI_TEST_NUPKG = $null
    }

    It 'treats the exact already-published package payload as an idempotent success' {
        $env:POSHUI_TEST_NUPKG = Join-Path $TestDrive 'matching.nupkg'
        New-PublishedPackageFixture `
            -SourcePath (Join-Path $script:RepositoryRoot 'powershell') `
            -DestinationPath $env:POSHUI_TEST_NUPKG
        Mock Find-PSResource {
            return [PSCustomObject]@{ Name = 'PoshUI'; Version = $env:POSHUI_TEST_VERSION }
        }
        Mock Save-PSResource {
            Copy-Item -LiteralPath $env:POSHUI_TEST_NUPKG -Destination (Join-Path $Path "PoshUI.$($env:POSHUI_TEST_VERSION).nupkg")
        }

        & $script:PublishScript -UserName 'ci-user' -Token 'secret' -FeedUri 'https://artifactory.example.test/api/nuget/v3/feed/index.json' -LookupUri 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'

        Should -Invoke Publish-PSResource -Times 0 -Exactly
        Should -Invoke Save-PSResource -Times 1 -Exactly
        Should -Invoke Write-Information -Times 1 -Exactly -ParameterFilter {
            $Message -eq "PoshUI $($env:POSHUI_TEST_VERSION) is already published with the exact expected payload."
        }
        Should -Invoke Unregister-PSResourceRepository -Times 2 -Exactly
    }

    It 'fails closed when the published version has different package content' {
        $env:POSHUI_TEST_NUPKG = Join-Path $TestDrive 'different.nupkg'
        New-PublishedPackageFixture `
            -SourcePath (Join-Path $script:RepositoryRoot 'powershell') `
            -DestinationPath $env:POSHUI_TEST_NUPKG `
            -DifferentPayload
        Mock Find-PSResource {
            return [PSCustomObject]@{ Name = 'PoshUI'; Version = $env:POSHUI_TEST_VERSION }
        }
        Mock Save-PSResource {
            Copy-Item -LiteralPath $env:POSHUI_TEST_NUPKG -Destination (Join-Path $Path "PoshUI.$($env:POSHUI_TEST_VERSION).nupkg")
        }

        {
            & $script:PublishScript -UserName 'ci-user' -Token 'secret' -FeedUri 'https://artifactory.example.test/api/nuget/v3/feed/index.json' -LookupUri 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'
        } | Should -Throw -ExpectedMessage "*PoshUI $($script:ManifestVersion)*different package content*"

        Should -Invoke Publish-PSResource -Times 0 -Exactly
        Should -Invoke Save-PSResource -Times 1 -Exactly
        Should -Invoke Unregister-PSResourceRepository -Times 2 -Exactly
    }

    It 'uses consumer metadata while keeping the writable feed as the publish target' {
        & $script:PublishScript `
            -UserName 'ci-user' `
            -Token 'secret' `
            -FeedUri 'https://artifactory.example.test/api/nuget/v3/feed/index.json' `
            -LookupUri 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'

        Should -Invoke Find-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PoshUI' -and $Version -eq $script:ManifestVersion -and $Repository -like 'posh-ui-lookup-*'
        }
        Should -Invoke Register-PSResourceRepository -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://artifactory.example.test/api/nuget/v3/feed/index.json'
        }
        Should -Invoke Register-PSResourceRepository -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'
        }
        Should -Invoke Publish-PSResource -Times 1 -Exactly
    }

    It 'publishes when the consumer repository has no exact version' {
        & $script:PublishScript -UserName 'ci-user' -Token 'secret' -FeedUri 'https://artifactory.example.test/api/nuget/v3/feed/index.json' -LookupUri 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'

        Should -Invoke Publish-PSResource -Times 1 -Exactly
    }

    It 'fails closed when the consumer repository lookup fails unexpectedly' {
        Mock Find-PSResource { throw 'consumer repository unavailable' }

        {
            & $script:PublishScript -UserName 'ci-user' -Token 'secret' -FeedUri 'https://artifactory.example.test/api/nuget/v3/feed/index.json' -LookupUri 'https://artifactory.example.test/api/nuget/v3/lookup/index.json'
        } | Should -Throw -ExpectedMessage '*consumer repository unavailable*'

        Should -Invoke Publish-PSResource -Times 0 -Exactly
    }
}

Describe 'Release workflow contract' {
    It 'excludes generated release commits before creating another pipeline' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $workflow = Get-CiJobBlock -Content $ci -Name 'workflow'

        $workflow | Should -Match 'CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH.*CI_COMMIT_MESSAGE.*chore\\\(release\\\): v'
        $workflow | Should -Match '(?m)^\s+when: never$'
    }

    It 'installs git for every job using the shared PowerShell image' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $sharedPowerShell = Get-CiJobBlock -Content $ci -Name '.pwsh'

        $sharedPowerShell | Should -Match 'apt-get install[^\r\n]+\bgit\b'
    }

    It 'requires the environment runtime locally and pins available CI environments' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $build = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'build.ps1') -Raw
        $windows = Get-CiJobBlock -Content $ci -Name 'pester-windows'

        $ci | Should -Match 'POWERSHELL_VERSION:\s*"7\.6\.4"'
        $build | Should -Match '(?m)^#Requires -Version 7\.6\r?$'
        $build | Should -Match '\[Environment\]::ProcessPath'
        $windows | Should -Match '\$installedVersion -ne \$env:POWERSHELL_VERSION'
    }

    It 'does not schedule work on an unavailable macOS runner' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw

        $ci | Should -Not -Match '(?m)^pester-macos:'
        $ci | Should -Not -Match '(?m)^\s+- macmini$'
    }

    It 'automatically releases and publishes a green default-branch squash' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $release = Get-CiJobBlock -Content $ci -Name 'automatic-release'
        $publish = [regex]::Match(
            $ci,
            '(?ms)^publish:\s*$(.*?)(?=^[a-zA-Z][a-zA-Z0-9-]*:\s*$)'
        ).Groups[1].Value

        $release | Should -Match '\$CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH'
        $release | Should -Match 'scripts/automatic_release\.sh'
        $release | Should -Not -Match '(?m)^\s+when: manual$'
        $release | Should -Not -Match 'CI_COMMIT_TAG'
        $publish | Should -Match '\$CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH'
        $publish | Should -Not -Match '(?m)^\s+when: manual$'
        $publish | Should -Not -Match 'CI_COMMIT_TAG'
    }

    It 'previews merge-request release intent without mutation or publication' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $preview = Get-CiJobBlock -Content $ci -Name 'version-not-released'
        $release = Get-CiJobBlock -Content $ci -Name 'automatic-release'
        $publish = Get-CiJobBlock -Content $ci -Name 'publish'

        $ci | Should -Match '\$CI_PIPELINE_SOURCE == "merge_request_event"'
        $preview | Should -Match 'Get-NextVersion\.ps1'
        $preview | Should -Not -Match '(?:-Apply|automatic_release|Publish-PoshUIModule|git\s+push)'
        $release | Should -Match '\$CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH'
        $release | Should -Not -Match 'merge_request_event'
        $publish | Should -Match '\$CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH'
        $publish | Should -Not -Match 'merge_request_event'
    }

    It 'serializes non-interruptible release operations' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $release = Get-CiJobBlock -Content $ci -Name 'automatic-release'
        $publish = Get-CiJobBlock -Content $ci -Name 'publish'

        $release | Should -Match '(?m)^\s+interruptible: false$'
        $release | Should -Match '(?m)^\s+resource_group: posh-ui-release$'
        $publish | Should -Match '(?m)^\s+interruptible: false$'
        $publish | Should -Match '(?m)^\s+resource_group: posh-ui-release$'
        $publish | Should -Match '(?ms)^\s+needs:\s+.*?job: automatic-release\s+.*?artifacts: true'
    }

    It 'publishes and records the exact tag produced by the branch pipeline' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw
        $release = Get-CiJobBlock -Content $ci -Name 'automatic-release'
        $publish = Get-CiJobBlock -Content $ci -Name 'publish'
        $gitlabRelease = Get-CiJobBlock -Content $ci -Name 'gitlab-release'

        $release | Should -Match '(?ms)^\s+artifacts:\s+.*?reports:\s+.*?dotenv: \.release/release\.env'
        $publish | Should -Match '\.release/version'
        $publish | Should -Match 'git\s+fetch[^\r\n]+refs/tags/'
        $publish | Should -Match 'git\s+checkout\s+--detach'
        $gitlabRelease | Should -Match 'POSHUI_RELEASE_TAG'
        $gitlabRelease | Should -Match 'GITLAB_HOST:\s*["'']?\$CI_SERVER_FQDN'
        $gitlabRelease | Should -Match 'GITLAB_TOKEN:\s*["'']?\$CI_JOB_TOKEN'
        $gitlabRelease | Should -Not -Match 'CI_COMMIT_TAG'
        $gitlabRelease | Should -Match '\$CI_COMMIT_BRANCH == \$CI_DEFAULT_BRANCH'
        $gitlabRelease | Should -Match '(?ms)^\s+needs:\s+.*?job: publish\s+.*?artifacts: true'
        $gitlabRelease | Should -Match '(?ms)\[\s+-z\s+["'']?\$\{?POSHUI_RELEASE_TAG.{0,200}?exit\s+0'
        $gitlabRelease | Should -Match 'glab\s+release\s+create'
        $gitlabRelease | Should -Match '--repo\s+["'']?\$CI_PROJECT_PATH'
        $gitlabRelease | Should -Not -Match 'glab\s+release\s+create[^\r\n]+--no-update'
        $gitlabRelease | Should -Match '\.release/notes\.md'
        $gitlabRelease | Should -Not -Match '(?m)^\s+release:$'
    }

    It 'fails closed, pushes the release atomically, and prevents release recursion' {
        Test-Path -LiteralPath $script:AutomaticReleaseScript -PathType Leaf | Should -BeTrue
        $release = Get-Content -LiteralPath $script:AutomaticReleaseScript -Raw

        $release | Should -Match 'CI_COMMIT_SHA'
        $release | Should -Match 'CI_DEFAULT_BRANCH'
        $release | Should -Match 'GITLAB_TOKEN'
        $release | Should -Match 'Get-NextVersion\.ps1'
        $release | Should -Match 'Nothing to release'
        $release | Should -Match '\[skip ci\]'
        $release | Should -Match 'git\s+push\s+--atomic'
    }

    It 'commits the version-bearing generated reference during release stamping' {
        $release = Get-Content -LiteralPath $script:AutomaticReleaseScript -Raw

        $release | Should -Match 'docs/reference/powershell\.md'
        $release | Should -Not -Match 'docs/reference/commands\.md'
    }

    It 'delegates Make targets to the PowerShell build entry point' {
        $makefile = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'Makefile') -Raw

        $makefile | Should -Match 'pwsh[^\r\n]+-File ./build\.ps1 -Task install'
        $makefile | Should -Match 'pwsh[^\r\n]+-File ./build\.ps1 -Task "\$@"'
    }

    It 'does not advertise repository-only documentation from the installed module' {
        $module = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'powershell/PoshUI.psm1') -Raw
        $module | Should -Not -Match 'docs/testing/TESTING\.md'
    }
}

Describe 'Runtime package artifact' {
    It 'compresses to a module-only nupkg that imports after expansion' {
        $stage = Join-Path $TestDrive 'stage'
        $output = Join-Path $TestDrive 'output'
        New-Item -ItemType Directory -Path $stage, $output -Force | Out-Null
        foreach ($entry in @('PoshUI.psd1', 'PoshUI.psm1', 'README.md', 'modules')) {
            Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'powershell' $entry) `
                -Destination $stage -Recurse -Force
        }

        Compress-PSResource -Path $stage -DestinationPath $output
        $package = @(Get-ChildItem $output -Filter '*.nupkg')
        $package | Should -HaveCount 1
        $expanded = Join-Path $TestDrive 'expanded'
        Expand-Archive $package[0].FullName $expanded
        foreach ($entry in @('bin', 'examples', 'tests', 'tools')) {
            Test-Path (Join-Path $expanded $entry) | Should -BeFalse
        }
        $expandedManifest = Join-Path $expanded 'PoshUI.psd1'
        { Test-ModuleManifest $expandedManifest -ErrorAction Stop } |
            Should -Not -Throw

        $probeScript = @'
$ErrorActionPreference = 'Stop'
$env:POSH_UI_MODE = 'off'
$module = Import-Module $env:POSHUI_PACKAGE_MANIFEST -Force -PassThru
@($module.ExportedCommands.Keys | Sort-Object) | ConvertTo-Json -Compress
'@
        $previousManifest = $env:POSHUI_PACKAGE_MANIFEST
        try {
            $env:POSHUI_PACKAGE_MANIFEST = $expandedManifest
            $output = & (Get-Process -Id $PID).Path -NoLogo -NoProfile -NonInteractive -Command $probeScript
        }
        finally {
            if ($null -eq $previousManifest) {
                Remove-Item Env:POSHUI_PACKAGE_MANIFEST -ErrorAction SilentlyContinue
            }
            else {
                $env:POSHUI_PACKAGE_MANIFEST = $previousManifest
            }
        }
        $LASTEXITCODE | Should -Be 0
        $expected = @((Import-PowerShellDataFile (Join-Path $stage 'PoshUI.psd1')).FunctionsToExport | Sort-Object)
        @($output | ConvertFrom-Json) | Should -Be $expected
        $expected | Should -HaveCount 82
    }
}
