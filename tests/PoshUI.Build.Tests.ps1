#Requires -Version 7.6

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:BuildScript = Join-Path $script:RepositoryRoot 'build.ps1'
    $script:PowerShellPath = [Environment]::ProcessPath

    function Invoke-PoshUIBuildTestProcess {
        param([string[]]$ArgumentList = @())

        $output = @(& $script:PowerShellPath `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -File $script:BuildScript `
                @ArgumentList 2>&1)

        [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output -join "`n")
        }
    }
}

Describe 'PowerShell build entry point' {
    It 'uses the environment PowerShell for child task processes' {
        $build = Get-Content -LiteralPath $script:BuildScript -Raw

        $build | Should -Match '\[Environment\]::ProcessPath'
    }

    It 'lists the repository task contract by default' {
        $result = Invoke-PoshUIBuildTestProcess

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Usage: pwsh ./build\.ps1 -Task <task>'
        foreach ($task in @(
            'install',
            'lint',
            'version-check',
            'manifest-check',
            'build',
            'docs',
            'docs-check',
            'test',
            'check',
            'ci',
            'release-plan',
            'release-apply',
            'clean'
        )) {
            $result.Output | Should -Match "(?m)^  $([regex]::Escape($task))\s+"
        }
    }

    It 'rejects an unknown task with a non-zero exit code' {
        $result = Invoke-PoshUIBuildTestProcess -ArgumentList @('-Task', 'unknown')

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'ValidateSet'
    }

    It 'runs the version consistency task in a clean child process' {
        $result = Invoke-PoshUIBuildTestProcess -ArgumentList @('-Task', 'version-check')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '==> version-check'
    }

    It 'runs build dependencies once and in declaration order' {
        $result = Invoke-PoshUIBuildTestProcess -ArgumentList @('-Task', 'build')

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Output, '(?m)^==> version-check$')).Count | Should -Be 1
        ([regex]::Matches($result.Output, '(?m)^==> manifest-check$')).Count | Should -Be 1
        ([regex]::Matches($result.Output, '(?m)^==> build$')).Count | Should -Be 1
        $result.Output.IndexOf('==> version-check') | Should -BeLessThan $result.Output.IndexOf('==> manifest-check')
        $result.Output.IndexOf('==> manifest-check') | Should -BeLessThan $result.Output.IndexOf('==> build')
    }
}
