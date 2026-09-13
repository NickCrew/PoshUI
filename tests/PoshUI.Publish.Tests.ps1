#Requires -Version 7.6

BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:PublishScript = Join-Path $script:RepositoryRoot 'tools/Publish-PoshUIModule.ps1'
    $script:AutomaticReleaseScript = Join-Path $script:RepositoryRoot 'scripts/automatic_release.sh'
    $script:WorkflowPath = Join-Path $script:RepositoryRoot '.github/workflows/ci.yml'
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'powershell/PoshUI.psd1'
    $script:ManifestVersion = (Import-PowerShellDataFile -Path $script:ManifestPath).ModuleVersion

    function Get-WorkflowJobBlock {
        param(
            [Parameter(Mandatory)][string]$Content,
            [Parameter(Mandatory)][string]$Name
        )

        $escaped = [regex]::Escape($Name)
        return [regex]::Match(
            $Content,
            "(?ms)^  ${escaped}:\s*`$(.*?)(?=^  [a-zA-Z][a-zA-Z0-9_-]*:\s*`$|\z)"
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
        $env:PSGALLERY_API_KEY = $null
        $env:POSHUI_TEST_VERSION = $script:ManifestVersion
        $env:POSHUI_TEST_NUPKG = $null

        Mock Publish-PSResource {}
        Mock Find-PSResource {}
        Mock Save-PSResource {}
        Mock Write-Information {}
    }

    AfterEach {
        $env:PSGALLERY_API_KEY = $null
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

        & $script:PublishScript -ApiKey 'secret'

        Should -Invoke Publish-PSResource -Times 0 -Exactly
        Should -Invoke Save-PSResource -Times 1 -Exactly
        Should -Invoke Write-Information -Times 1 -Exactly -ParameterFilter {
            $Message -eq "PoshUI $($env:POSHUI_TEST_VERSION) is already published with the exact expected payload."
        }
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
            & $script:PublishScript -ApiKey 'secret'
        } | Should -Throw -ExpectedMessage "*PoshUI $($script:ManifestVersion)*different package content*"

        Should -Invoke Publish-PSResource -Times 0 -Exactly
        Should -Invoke Save-PSResource -Times 1 -Exactly
    }

    It 'looks up and publishes against the PowerShell Gallery using the supplied API key' {
        & $script:PublishScript -ApiKey 'secret'

        Should -Invoke Find-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PoshUI' -and $Version -eq $script:ManifestVersion -and $Repository -eq 'PSGallery'
        }
        Should -Invoke Publish-PSResource -Times 1 -Exactly -ParameterFilter {
            $Repository -eq 'PSGallery' -and $ApiKey -eq 'secret'
        }
    }

    It 'publishes when the gallery has no exact version' {
        & $script:PublishScript -ApiKey 'secret'

        Should -Invoke Publish-PSResource -Times 1 -Exactly
    }

    It 'fails closed when the gallery lookup fails unexpectedly' {
        Mock Find-PSResource { throw 'gallery unavailable' }

        {
            & $script:PublishScript -ApiKey 'secret'
        } | Should -Throw -ExpectedMessage '*gallery unavailable*'

        Should -Invoke Publish-PSResource -Times 0 -Exactly
    }

    It 'requires an API key from a parameter or the environment' {
        {
            & $script:PublishScript
        } | Should -Throw -ExpectedMessage '*PSGALLERY_API_KEY*'

        Should -Invoke Publish-PSResource -Times 0 -Exactly
    }
}

Describe 'Release workflow contract' {
    It 'runs the release chain only on a direct push to main, never on a pull request' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $release = Get-WorkflowJobBlock -Content $ci -Name 'automatic-release'
        $publish = Get-WorkflowJobBlock -Content $ci -Name 'publish'

        $release | Should -Match 'if:\s*"?github\.event_name == ''push'''
        $release | Should -Match 'chore\(release\): v'
        $publish | Should -Match 'needs\.automatic-release\.outputs\.release_tag'
    }

    It 'installs the pinned PowerShell version for every job that needs it' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $action = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/actions/setup-pwsh/action.yml') -Raw

        $ci | Should -Match 'POWERSHELL_VERSION:\s*"7\.6\.4"'
        $action | Should -Match 'sha256sum --check --status'
    }

    It 'does not schedule work on an unavailable macOS runner' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw

        $ci | Should -Not -Match 'runs-on:\s*macos-'
    }

    It 'runs the Windows Pester job on the windows-latest runner' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $windows = Get-WorkflowJobBlock -Content $ci -Name 'pester-windows'

        $windows | Should -Match 'runs-on:\s*windows-latest'
        $windows | Should -Match '\$installedVersion -ne \$env:POWERSHELL_VERSION'
    }

    It 'automatically releases and publishes a green default-branch push' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $release = Get-WorkflowJobBlock -Content $ci -Name 'automatic-release'
        $publish = Get-WorkflowJobBlock -Content $ci -Name 'publish'

        $release | Should -Match 'scripts/automatic_release\.sh'
        $publish | Should -Match 'Publish-PoshUIModule\.ps1'
        $publish | Should -Match 'needs:\s*automatic-release'
    }

    It 'serializes release operations across concurrent runs' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw

        $ci | Should -Match '(?m)^concurrency:$'
        $ci | Should -Match 'group:\s*posh-ui-release'
    }

    It 'publishes and records the exact tag produced by the release job' {
        $ci = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $publish = Get-WorkflowJobBlock -Content $ci -Name 'publish'
        $githubRelease = Get-WorkflowJobBlock -Content $ci -Name 'github-release'

        $publish | Should -Match 'git\s+fetch[^\r\n]+refs/tags/'
        $publish | Should -Match 'git\s+checkout\s+--detach'
        $githubRelease | Should -Match 'needs:\s*\[automatic-release, publish\]'
        $githubRelease | Should -Match 'gh\s+release\s+create'
        $githubRelease | Should -Match '\.release/notes\.md'
    }

    It 'fails closed, pushes the release atomically, and prevents release recursion' {
        Test-Path -LiteralPath $script:AutomaticReleaseScript -PathType Leaf | Should -BeTrue
        $release = Get-Content -LiteralPath $script:AutomaticReleaseScript -Raw

        $release | Should -Match 'GITHUB_SHA'
        $release | Should -Match 'DEFAULT_BRANCH'
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
