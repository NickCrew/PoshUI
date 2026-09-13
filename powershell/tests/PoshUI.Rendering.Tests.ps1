#Requires -Version 7.6

BeforeAll {
    $script:BoxesPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'modules' 'Boxes.psm1'
}

Describe 'Composable box rendering' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Boxes -Force -ErrorAction SilentlyContinue
        Import-Module $script:BoxesPath -Force
    }

    AfterEach {
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
        Remove-Module Boxes -Force -ErrorAction SilentlyContinue
    }

    It 'returns exact plain-mode lines without host output' {
        $information = [System.Collections.Generic.List[object]]::new()
        $lines = @(Format-PoshUIBox -Title 'Status' -Content 'Ready' -Width 12 -InformationVariable information)

        $lines | Should -Be @(
            '╔══════════╗'
            '║  Status  ║'
            '╠══════════╣'
            '║ Ready    ║'
            '╚══════════╝'
        )
        $information | Should -BeNullOrEmpty
    }

    It 'composes formatter output with ordinary pipeline transformations' {
        $composed = @('One', 'Two' | Format-PoshUIBox -Title 'Items' -Width 12 | ForEach-Object { "> $_" })

        $composed | Should -Be @(
            '> ╔══════════╗'
            '> ║  Items   ║'
            '> ╠══════════╣'
            '> ║ One      ║'
            '> ║ Two      ║'
            '> ╚══════════╝'
        )
    }

    It 'truncates long titles and content to the requested width' {
        $lines = @(Format-PoshUIBox -Title ('T' * 20) -Content ('x' * 20) -Width 10)

        $lines | ForEach-Object { $_.Length | Should -Be 10 }
        ($lines -join "`n") | Should -Not -Match ('x' * 20)
    }

    It 'routes display output through the runtime boundary' {
        $displayed = @(& { Show-PoshUIBox -Title 'Status' -Content 'Ready' -Width 12 } 6>&1 | ForEach-Object MessageData)
        $formatted = @(Format-PoshUIBox -Title 'Status' -Content 'Ready' -Width 12)

        $displayed | Should -Be $formatted
    }
}
