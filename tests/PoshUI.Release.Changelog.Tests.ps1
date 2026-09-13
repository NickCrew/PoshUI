#Requires -Version 7.6

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ReleaseTool = Join-Path $script:RepoRoot 'tools/Invoke-ReleaseChangelog.ps1'
    $script:VersionTool = Join-Path $script:RepoRoot 'tools/Get-NextVersion.ps1'
    $script:SetVersionTool = Join-Path $script:RepoRoot 'tools/Set-Version.ps1'
    $script:VersionSites = @(
        'powershell/PoshUI.psd1',
        'README.md'
    )

    function New-ReleaseRepository {
        param([Parameter(Mandatory)][string]$Path)

        foreach ($relative in @('tools/Invoke-ReleaseChangelog.ps1', 'tools/Get-NextVersion.ps1', 'tools/Set-Version.ps1') + $script:VersionSites) {
            $destination = Join-Path $Path $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot $relative) -Destination $destination
        }
        Set-Content -LiteralPath (Join-Path $Path 'CHANGELOG.md') -Value @'
# Changelog

## [Unreleased]

## [2.1.1] - 2026-01-01

- Baseline.

[Unreleased]: https://github.example.test/group/project/compare/v2.1.1...HEAD
[2.1.1]: https://github.example.test/group/project/releases/tag/v2.1.1
'@

        & git -C $Path init --quiet --initial-branch=master
        & git -C $Path config core.autocrlf false
        & git -C $Path config core.safecrlf false
        & git -C $Path config user.name 'Release Test'
        & git -C $Path config user.email 'release@example.test'
        & git -C $Path add .
        & git -C $Path commit --quiet -m 'chore: baseline'
        & git -C $Path tag v2.1.1
    }

    function Add-ReleaseCommit {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Subject
        )

        Add-Content -LiteralPath (Join-Path $Path 'change.txt') -Value $Subject
        & git -C $Path add .
        & git -C $Path commit --quiet -m $Subject
    }
}

Describe 'Release changelog contract' {
    It 'exports exact version notes for the automatic publish job' {
        $ci = [IO.File]::ReadAllText((Join-Path $script:RepoRoot '.github/workflows/ci.yml'))

        $publish = [regex]::Match($ci, '(?ms)^  publish:\s*$(.*?)(?=^  [a-zA-Z][a-zA-Z0-9_-]*:\s*$|\z)').Groups[1].Value
        $githubRelease = [regex]::Match($ci, '(?ms)^  github-release:\s*$(.*?)(?=^  [a-zA-Z][a-zA-Z0-9_-]*:\s*$|\z)').Groups[1].Value
        $publish | Should -Match 'Invoke-ReleaseChangelog\.ps1 -Action Verify'
        $publish | Should -Match '\.release/notes\.md'
        $githubRelease | Should -Match '\.release/notes\.md'
        $githubRelease | Should -Match 'gh\s+release\s+create'
    }

    It 'rolls curated Unreleased notes when applying the derived version' {
        $repo = Join-Path $TestDrive 'curated'
        New-ReleaseRepository -Path $repo
        $changelog = Join-Path $repo 'CHANGELOG.md'
        $content = [regex]::Replace(
            [IO.File]::ReadAllText($changelog),
            '(?m)^## \[Unreleased\]\r?\n',
            "## [Unreleased]`n`n### Added`n`n- A deliberately curated operator note.`n"
        )
        [IO.File]::WriteAllText($changelog, $content)
        Add-ReleaseCommit -Path $repo -Subject 'feat(rendering): add compact tables'

        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply

        (Import-PowerShellDataFile (Join-Path $repo 'powershell/PoshUI.psd1')).ModuleVersion |
            Should -Be '2.2.0'
        & (Join-Path $repo 'tools/Set-Version.ps1') -Check
        $LASTEXITCODE | Should -Be 0
        $result = [IO.File]::ReadAllText($changelog)
        $result | Should -Match '(?ms)^## \[2\.2\.0\] - \d{4}-\d{2}-\d{2}\s+### Added\s+- A deliberately curated operator note\.'
        $result | Should -Not -Match 'add compact tables \([0-9a-f]{8}\)'
    }

    It 'generates fallback notes from releasable Conventional Commits' {
        $repo = Join-Path $TestDrive 'generated'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'fix(menu): preserve the selected item'
        $hash = (& git -C $repo rev-parse --short=8 HEAD).Trim()

        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply

        $result = [IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
        $result | Should -Match '### Changed'
        $result | Should -Match "fix\(menu\): preserve the selected item \($hash\)"
    }

    It 'makes a documentation-only housekeeping squash a no-op' {
        $repo = Join-Path $TestDrive 'housekeeping'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'docs(posh-ui): clarify installation'
        $beforeManifest = [IO.File]::ReadAllText((Join-Path $repo 'powershell/PoshUI.psd1'))
        $beforeChangelog = [IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))

        $version = & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply

        $version | Should -BeNullOrEmpty
        [IO.File]::ReadAllText((Join-Path $repo 'powershell/PoshUI.psd1')) | Should -BeExactly $beforeManifest
        [IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md')) | Should -BeExactly $beforeChangelog
        (& git -C $repo status --porcelain) | Should -BeNullOrEmpty
    }

    It 'excludes repository-only scopes unless they are breaking' {
        foreach ($scope in @('ci', 'docs', 'test', 'build', 'release', 'tooling')) {
            $repo = Join-Path $TestDrive "excluded-$scope"
            New-ReleaseRepository -Path $repo
            Add-ReleaseCommit -Path $repo -Subject "fix($scope): housekeeping"
            & (Join-Path $repo 'tools/Get-NextVersion.ps1') | Should -BeNullOrEmpty
        }

        $breakingRepo = Join-Path $TestDrive 'breaking-docs'
        New-ReleaseRepository -Path $breakingRepo
        Add-ReleaseCommit -Path $breakingRepo -Subject 'docs(api)!: remove compatibility contract'
        & (Join-Path $breakingRepo 'tools/Get-NextVersion.ps1') | Should -BeExactly '3.0.0'
    }

    It 'releases package fixes that change the immutable artifact' {
        $repo = Join-Path $TestDrive 'package-fix'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'fix(package): correct the packaged payload'

        & (Join-Path $repo 'tools/Get-NextVersion.ps1') | Should -BeExactly '2.1.2'
    }

    It 'does not derive another release after the release commit is tagged' {
        $repo = Join-Path $TestDrive 'no-recursion'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'fix(menu): preserve the selected item'
        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply
        & git -C $repo add .
        & git -C $repo commit --quiet -m 'chore(release): v2.1.2 [skip ci]'
        & git -C $repo tag v2.1.2

        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply | Should -BeNullOrEmpty
        (& git -C $repo status --porcelain) | Should -BeNullOrEmpty
    }

    It 'leaves every version site and the worktree unchanged when changelog validation fails' {
        $repo = Join-Path $TestDrive 'invalid-changelog'
        New-ReleaseRepository -Path $repo
        $changelog = Join-Path $repo 'CHANGELOG.md'
        $content = [IO.File]::ReadAllText($changelog).Replace('## [Unreleased]', '## [Draft]')
        [IO.File]::WriteAllText($changelog, $content)
        Add-ReleaseCommit -Path $repo -Subject 'fix(menu): reject malformed notes'
        $before = @{}
        foreach ($relative in $script:VersionSites) {
            $before[$relative] = [IO.File]::ReadAllText((Join-Path $repo $relative))
        }

        { & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply } |
            Should -Throw '*Unreleased*'

        foreach ($relative in $script:VersionSites) {
            [IO.File]::ReadAllText((Join-Path $repo $relative)) | Should -BeExactly $before[$relative]
        }
        (& git -C $repo status --porcelain) | Should -BeNullOrEmpty
    }

    It 'verifies tag, manifest, and changelog agreement and extracts exact notes' {
        $repo = Join-Path $TestDrive 'verify'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'fix(menu): preserve the selected item'
        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply
        & git -C $repo add .
        & git -C $repo commit --quiet -m 'chore(release): 2.1.2'
        & git -C $repo tag v2.1.2
        $notes = Join-Path $repo '.release/notes.md'

        & (Join-Path $repo 'tools/Invoke-ReleaseChangelog.ps1') `
            -Action Verify `
            -Tag v2.1.2 `
            -ManifestPath (Join-Path $repo 'powershell/PoshUI.psd1') `
            -OutputPath $notes

        [IO.File]::ReadAllText($notes) | Should -Match 'preserve the selected item'
        {
            & (Join-Path $repo 'tools/Invoke-ReleaseChangelog.ps1') `
                -Action Verify `
                -Tag v9.9.9 `
                -ManifestPath (Join-Path $repo 'powershell/PoshUI.psd1')
        } | Should -Throw '*does not match the manifest*'
    }

    It 'rejects undated, impossible-date, and placeholder release sections' {
        $repo = Join-Path $TestDrive 'invalid-version-section'
        New-ReleaseRepository -Path $repo
        Add-ReleaseCommit -Path $repo -Subject 'fix(menu): preserve the selected item'
        & (Join-Path $repo 'tools/Get-NextVersion.ps1') -Apply
        $changelog = Join-Path $repo 'CHANGELOG.md'
        $valid = [IO.File]::ReadAllText($changelog)
        $manifest = Join-Path $repo 'powershell/PoshUI.psd1'

        $undated = $valid -replace '## \[2\.1\.2\] - \d{4}-\d{2}-\d{2}', '## [2.1.2]'
        [IO.File]::WriteAllText($changelog, $undated)
        { & (Join-Path $repo 'tools/Invoke-ReleaseChangelog.ps1') -Action Verify -Tag v2.1.2 -ManifestPath $manifest } |
            Should -Throw '*dated heading*'

        $impossible = $valid -replace '## \[2\.1\.2\] - \d{4}-\d{2}-\d{2}', '## [2.1.2] - 2026-02-30'
        [IO.File]::WriteAllText($changelog, $impossible)
        { & (Join-Path $repo 'tools/Invoke-ReleaseChangelog.ps1') -Action Verify -Tag v2.1.2 -ManifestPath $manifest } |
            Should -Throw '*real calendar date*'

        $placeholder = [regex]::Replace(
            $valid,
            '(?ms)(^## \[2\.1\.2\] - \d{4}-\d{2}-\d{2}\r?\n).*?(?=^## \[)',
            "`${1}`nTBD`n`n"
        )
        [IO.File]::WriteAllText($changelog, $placeholder)
        { & (Join-Path $repo 'tools/Invoke-ReleaseChangelog.ps1') -Action Verify -Tag v2.1.2 -ManifestPath $manifest } |
            Should -Throw '*placeholder release notes*'
    }
}
