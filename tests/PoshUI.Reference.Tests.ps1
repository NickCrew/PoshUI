#Requires -Version 7.6

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:GeneratorPath = Join-Path $script:RepositoryRoot 'tools' 'Update-Docs.ps1'
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'powershell' 'PoshUI.psd1'
    $script:ReferenceRoot = Join-Path $script:RepositoryRoot 'docs' 'reference'
    $script:ReferencePath = Join-Path $script:ReferenceRoot 'powershell.md'
}

Describe 'Generated command reference' {
    It 'matches the explicit public API inventory' {
        & $script:GeneratorPath -ManifestPath $script:ManifestPath -OutputRoot $script:ReferenceRoot -Check
    }

    It 'contains one section for every supported command' {
        $content = Get-Content -LiteralPath $script:ReferencePath -Raw
        $declared = @((Import-PowerShellDataFile -LiteralPath $script:ManifestPath).FunctionsToExport)

        foreach ($name in $declared) {
            $content | Should -Match "(?m)^## $([regex]::Escape($name))$"
        }
    }

    It 'includes navigable summaries and full help sections' {
        $content = Get-Content -LiteralPath $script:ReferencePath -Raw

        $content | Should -Match '(?m)^\| Command \| Synopsis \|$'
        $content | Should -Match '(?m)^### Description$'
        $content | Should -Match '(?m)^### Parameters$'
        $content | Should -Match '(?m)^### Inputs$'
        $content | Should -Match '(?m)^### Outputs$'
        $content | Should -Match '(?m)^### Examples$'
        $content | Should -Match '(?m)^### Notes$'
    }

    It 'keeps local Markdown links resolvable' {
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($file in (Get-ChildItem $script:RepositoryRoot -Recurse -Filter '*.md' -File)) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($match in [regex]::Matches($content, '!?\[[^\]]*\]\((?<target>[^)]+)\)')) {
                $target = $match.Groups['target'].Value.Trim('<', '>')
                if ($target -match '^(?:https?://|mailto:|#)') { continue }
                $relativePath = ($target -split '#', 2)[0]
                if (-not $relativePath) { continue }
                $resolved = Join-Path $file.DirectoryName $relativePath
                if (-not (Test-Path -LiteralPath $resolved)) {
                    $missing.Add("$($file.FullName): $target")
                }
            }
        }

        $missing | Should -BeNullOrEmpty
    }
}
