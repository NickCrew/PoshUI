#Requires -Version 7.6

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
    $script:Manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
    $env:POSH_UI_MODE = 'off'
    $script:Module = Import-Module $script:ManifestPath -Force -PassThru -ErrorAction Stop
}

AfterAll {
    Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
}

Describe 'Native PoshUI module contract' {
    It 'imports the exact manifest inventory' {
        $declared = @($script:Manifest.FunctionsToExport | Sort-Object)
        $exported = @($script:Module.ExportedCommands.Keys | Sort-Object)
        Compare-Object $declared $exported | Should -BeNullOrEmpty
        $exported | Should -HaveCount 82
    }

    It 'exports only approved Verb-PoshUI noun commands' {
        $invalid = @($script:Module.ExportedCommands.Keys | Where-Object {
            $_ -notmatch '^[A-Z][a-z]+-PoshUI[A-Za-z]+$'
        })
        $invalid | Should -BeNullOrEmpty
    }

    It 'does not export the v3 compatibility families' {
        @($script:Module.ExportedCommands.Keys | Where-Object {
            $_ -like 'po_*' -or $_ -like 'posh_ui_*' -or $_ -like '_*'
        }) | Should -BeNullOrEmpty
    }

    It 'loads every declared feature without publishing loaded flags' {
        $script:Module.ExportedCommands.Keys | Should -Contain 'Format-PoshUIBox'
        $script:Module.ExportedCommands.Keys | Should -Contain 'Read-PoshUIText'
        @([Environment]::GetEnvironmentVariables().Keys | Where-Object {
            $_ -like 'POSH_UI_*_LOADED'
        }) | Should -BeNullOrEmpty
    }
}
