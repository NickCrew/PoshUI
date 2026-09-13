#Requires -Version 7.6

BeforeAll {
    $script:OriginalPoshUIMode = $env:POSH_UI_MODE
    $script:OriginalPoGreen = $env:PO_GREEN
    $script:OriginalPoReset = $env:PO_RESET
    $script:ChartsModulePath = Join-Path $PSScriptRoot '../modules/Charts.psm1'
}

AfterAll {
    $env:POSH_UI_MODE = $script:OriginalPoshUIMode
    $env:PO_GREEN = $script:OriginalPoGreen
    $env:PO_RESET = $script:OriginalPoReset
    Remove-Module Charts -Force -ErrorAction SilentlyContinue
}

Describe 'Composable chart formatting' {
    Context 'plain mode' {
        BeforeEach {
            $env:POSH_UI_MODE = 'plain'
            Remove-Module Charts, Runtime -Force -ErrorAction SilentlyContinue
            Import-Module $script:ChartsModulePath -Force
        }

        It 'returns exact horizontal bar chart lines without ANSI sequences' {
            $actual = @(Format-PoshUIHorizontalBarChart -Title 'Jobs' -Data 1, 2 -Labels 'A', 'B' -Width 4)

            $actual | Should -HaveCount 4
            $actual[0] | Should -BeExactly 'Jobs'
            $actual[1] | Should -BeExactly ''
            $actual[2] | Should -BeExactly 'A ██ 1'
            $actual[3] | Should -BeExactly 'B ████ 2'
            ($actual -join '') | Should -Not -Match "`e\["
        }

        It 'returns an exact sparkline string' {
            Format-PoshUISparkline -Data 0, 1, 2, 3 | Should -BeExactly '▁▃▆█'
        }

        It 'returns an exact gauge line without ANSI sequences' {
            Format-PoshUIGauge -Value 2 -Max 4 -Label 'Load' -Width 4 |
                Should -BeExactly 'Load: [██░░] 50.0% (2/4)'
        }
    }

    Context 'rich mode' {
        BeforeEach {
            $env:POSH_UI_MODE = 'rich'
            Remove-Module Charts, Runtime -Force -ErrorAction SilentlyContinue
            Import-Module $script:ChartsModulePath -Force
        }

        It 'preserves ANSI sequences in formatted output' {
            $actual = Format-PoshUIGauge -Value 3 -Max 4 -Width 4

            $actual | Should -Match "`e\["
            ([regex]::Replace($actual, "`e\[[0-9;?]*[ -/]*[@-~]", '')) |
                Should -BeExactly '[███░] 75.0% (3/4)'
        }
    }

    It 'rejects mismatched horizontal chart labels' {
        $env:POSH_UI_MODE = 'plain'

        { Format-PoshUIHorizontalBarChart -Data 1, 2 -Labels 'Only one' } |
            Should -Throw '*one label for every data value*'
    }

    It 'rejects a gauge value above its maximum' {
        { Format-PoshUIGauge -Value 5 -Max 4 } | Should -Throw '*greater than Max*'
    }
}

Describe 'Chart display wrappers' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Charts, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:ChartsModulePath -Force
    }

    It 'writes each horizontal chart line through the runtime boundary' {
        InModuleScope Charts {
            Mock Write-PoshUIHost {}

            Show-PoshUIHorizontalBarChart -Title 'Jobs' -Data 1 -Width 2

            Should -Invoke Write-PoshUIHost -Exactly 3
        }
    }

    It 'keeps sparkline display inline by default' {
        InModuleScope Charts {
            Mock Write-PoshUIHost {}

            Show-PoshUISparkline -Data 1, 2

            Should -Invoke Write-PoshUIHost -Exactly 1 -ParameterFilter { $NoNewline }
        }
    }

    It 'routes the gauge command through the runtime boundary' {
        InModuleScope Charts {
            Mock Write-PoshUIHost {}

            Show-PoshUIGauge -Value 1 -Max 2 -Label 'CPU' -Width 5

            Should -Invoke Write-PoshUIHost -Exactly 1
        }
    }
}
