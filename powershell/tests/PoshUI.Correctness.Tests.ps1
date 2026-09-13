#Requires -Version 7.6

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
}

Describe 'Native prompt correctness' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        $script:Module = Import-Module $script:ManifestPath -Force -PassThru
    }

    AfterEach {
        Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'exports the complete prompt family' {
        $expected = @(
            'Read-PoshUIText', 'Read-PoshUIPassword', 'Confirm-PoshUIChoice'
            'Select-PoshUIOption', 'Select-PoshUIMultipleOption', 'Read-PoshUINumber'
            'Read-PoshUIFilePath', 'Read-PoshUIDirectoryPath'
        )
        foreach ($name in $expected) {
            $script:Module.ExportedCommands.Keys | Should -Contain $name
        }
    }

    It 'returns explicit defaults without an interactive input stream' {
        Read-PoshUIText -Message Name -Default 'Ada' | Should -BeExactly 'Ada'
        Read-PoshUINumber -Message Count -Default 3 | Should -Be 3
        Confirm-PoshUIChoice -Message Continue | Should -BeFalse
    }

    It 'fails safely when required input cannot be read' {
        { Read-PoshUIText -Message Name } | Should -Throw '*interactive*'
        { Read-PoshUIPassword -Message Password } | Should -Throw '*interactive*'
        { Read-PoshUIFilePath -Message File } | Should -Throw '*interactive*'
        { Read-PoshUIDirectoryPath -Message Directory } | Should -Throw '*interactive*'
    }

    It 'does not persist prompt history or secrets' {
        $moduleText = Get-Content (Join-Path $PSScriptRoot '../modules/Prompts.psm1') -Raw
        $moduleText | Should -Not -Match '(?i)history'
        $moduleText | Should -Not -Match 'PO_PROMPT'
    }
}

Describe 'Progress boundary correctness' {
    BeforeAll {
        $env:POSH_UI_MODE = 'plain'
        $script:ProgressModule = Import-Module $script:ManifestPath -Force -PassThru
    }

    AfterAll {
        Remove-Module -ModuleInfo $script:ProgressModule -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'rejects invalid totals and widths' {
        { New-PoshUIProgress -Total 0 } | Should -Throw
        { New-PoshUIProgress -Total 1 -Width 0 } | Should -Throw
    }

    It 'clamps current work to the model boundary' {
        (New-PoshUIProgress -Total 2 -Current 3).Current | Should -Be 2
    }
}
