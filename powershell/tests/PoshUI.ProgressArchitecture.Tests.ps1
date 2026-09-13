#Requires -Version 7.6

BeforeAll {
    $script:ProgressModulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules' 'Progress.psm1')).Path
}

Describe 'Independent progress models' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Progress, Configuration, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:ProgressModulePath -Force
    }

    AfterEach {
        Remove-Module Progress, Configuration, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'keeps interleaved models independent' {
        $first = New-PoshUIProgress -Total 10 -Label 'First' -Width 4
        $second = New-PoshUIProgress -Total 20 -Label 'Second' -Width 6

        $null = $first | Update-PoshUIProgress -Increment 3
        $null = $second | Update-PoshUIProgress -Increment 8
        $null = $first | Update-PoshUIProgress -Increment 2

        $first.Current | Should -Be 5
        $first.Total | Should -Be 10
        $first.Width | Should -Be 4
        $second.Current | Should -Be 8
        $second.Total | Should -Be 20
        $second.Width | Should -Be 6
    }

    It 'clamps updates to model boundaries' {
        $progress = New-PoshUIProgress -Total 5 -Current 4

        $null = $progress | Update-PoshUIProgress -Increment 20
        $progress.Current | Should -Be 5

        $null = $progress | Update-PoshUIProgress -Increment -20
        $progress.Current | Should -Be 0
    }

    It 'formats exact composable plain output without mutation' {
        $progress = New-PoshUIProgress -Total 4 -Current 2 -Label 'Work' -Width 4

        $before = $progress.PSObject.Copy()
        $line = $progress | Format-PoshUIProgress

        $line | Should -Be 'Work [██░░]  50% (2/4)'
        $progress.Current | Should -Be $before.Current
        $progress.Label | Should -Be $before.Label
    }

    It 'composes formatted output from multiple models in pipeline order' {
        $first = New-PoshUIProgress -Total 2 -Current 1 -Label 'One' -Width 2
        $second = New-PoshUIProgress -Total 4 -Current 4 -Label 'Two' -Width 2

        $lines = @($first, $second) | Format-PoshUIProgress

        $lines | Should -HaveCount 2
        $lines[0] | Should -Be 'One [█░]  50% (1/2)'
        $lines[1] | Should -Be 'Two [██] 100% (4/4)'
    }

    It 'strips caller-supplied ANSI colors in plain mode' {
        $env:PO_CYAN = "`e[36m"
        $env:PO_RESET = "`e[0m"
        try {
            $progress = New-PoshUIProgress -Total 2 -Current 1 -Label 'Work' -Width 2
            $progress | Format-PoshUIProgress | Should -Be 'Work [█░]  50% (1/2)'
        }
        finally {
            Remove-Item Env:\PO_CYAN, Env:\PO_RESET -ErrorAction SilentlyContinue
        }
    }

}
