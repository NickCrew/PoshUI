#Requires -Version 7.6

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'powershell/PoshUI.psd1'
}

Describe 'PowerShell runtime policy' {
    It 'requires PowerShell Core 7.6 in the module manifest' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        [version]$manifest.PowerShellVersion | Should -Be ([version]'7.6')
        @($manifest.CompatiblePSEditions) | Should -Be @('Core')
    }

    It 'requires 7.6 in every PowerShell source file' {
        $files = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File -Include '*.ps1', '*.psm1')
        $missing = @($files | Where-Object {
            (Get-Content -LiteralPath $_.FullName -TotalCount 1) -ne '#Requires -Version 7.6'
        } | ForEach-Object FullName)
        $missing | Should -BeNullOrEmpty
    }

    It 'requires the environment PowerShell locally and pins the CI runtime' {
        (Get-Content (Join-Path $script:RepositoryRoot 'build.ps1') -TotalCount 1) | Should -Be '#Requires -Version 7.6'
        (Get-Content (Join-Path $script:RepositoryRoot '.gitlab-ci.yml') -Raw) | Should -Match 'POWERSHELL_VERSION:\s*"7\.6\.'
    }

    It 'keeps removed compatibility commands out of runtime and tooling code' {
        $roots = @(
            (Join-Path $script:RepositoryRoot 'powershell')
            (Join-Path $script:RepositoryRoot 'tools')
        )
        $files = @(Get-ChildItem -LiteralPath $roots -Recurse -File -Include '*.ps1', '*.psm1' |
                Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)tests$([IO.Path]::DirectorySeparatorChar)*" })
        $legacyNames = foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $ast.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.FunctionDefinitionAst] -or
                    $node -is [Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object {
                $name = if ($_ -is [Management.Automation.Language.FunctionDefinitionAst]) {
                    $_.Name
                }
                else {
                    $_.GetCommandName()
                }
                if ($name -match '^(po_|posh_ui_)') { "$($file.FullName):$($_.Extent.StartLineNumber):$name" }
            }
        }
        @($legacyNames) | Should -BeNullOrEmpty
    }
}
