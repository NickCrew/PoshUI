#Requires -Version 7.6

BeforeAll {
    $script:TableModulePath = Join-Path $PSScriptRoot '..' 'modules' 'Tables.psm1'
    Import-Module $script:TableModulePath -Force

    $env:PO_TABLE_BORDER_COLOR = ''
    $env:PO_TABLE_HEADER_COLOR = ''
    $env:PO_RESET = ''
}
Describe 'PoshUI table instances' {
    It 'keeps interleaved table mutations independent' {
        $first = New-PoshUITable -Style Simple -Header Name, Value
        $second = New-PoshUITable -Style Rounded -Header Service, State

        Add-PoshUITableRow -Table $first -Values alpha, 1
        Add-PoshUITableRow -Table $second -Values api, healthy
        Add-PoshUITableRow -Table $first -Values beta, 22
        Set-PoshUITableAlignment -Table $first -Column 1 -Alignment Right

        $first.Rows.Count | Should -Be 2
        $first.Rows[0] | Should -Be @('alpha', 1)
        $first.Rows[1] | Should -Be @('beta', 22)
        $first.Alignments | Should -Be @('left', 'right')
        $second.Rows.Count | Should -Be 1
        $second.Rows[0] | Should -Be @('api', 'healthy')
        $second.Alignments | Should -Be @('left', 'left')
    }

    It 'accepts pipeline objects in property order' {
        $table = New-PoshUITable -Style Simple -Header Name, Score
        @(
            [pscustomobject]@{ Score = 7; Name = 'Ada' }
            [pscustomobject]@{ Score = 12; Name = 'Grace' }
        ) | Add-PoshUITableRow -Table $table -Property Name, Score

        $table.Rows.Count | Should -Be 2
        $table.Rows[0] | Should -Be @('Ada', 7)
        $table.Rows[1] | Should -Be @('Grace', 12)
    }
}

Describe 'PoshUI table formatting' {
    It 'returns exact line strings without writing to the host' {
        $table = New-PoshUITable -Style Simple -Header Name, Value
        Add-PoshUITableRow -Table $table -Values alpha, 7

        $information = @()
        $actual = @(Format-PoshUITable -Table $table -InformationVariable information)

        $actual | Should -Be @(
            '+-------+-------+'
            '| Name  | Value |'
            '+-------+-------+'
            '| alpha | 7     |'
            '+-------+-------+'
        )
        $information.Count | Should -Be 0
    }

    It 'does not mutate state while formatting repeatedly' {
        $table = New-PoshUITable -Style Simple -Header Name, Value
        Add-PoshUITableRow -Table $table -Values alpha, 7
        $before = $table | ConvertTo-Json -Depth 5 -Compress

        $first = @(Format-PoshUITable $table)
        $second = @(Format-PoshUITable $table)

        $second | Should -Be $first
        ($table | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly $before
    }

    It 'pads short rows and headers to the complete rendered width' {
        $table = New-PoshUITable -Style Simple -Header A, B
        Add-PoshUITableRow -Table $table -Values 1
        Add-PoshUITableRow -Table $table -Values 2, 3, 4

        $actual = @(Format-PoshUITable $table)

        $actual[1] | Should -Be '| A | B |   |'
        $actual[3] | Should -Be '| 1 |   |   |'
        $actual[4] | Should -Be '| 2 | 3 | 4 |'
        $actual | ForEach-Object { $_.Length | Should -Be $actual[0].Length }
    }

    It 'strips caller-supplied ANSI colors in plain mode' {
        $env:PO_TABLE_BORDER_COLOR = "`e[31m"
        $env:PO_TABLE_HEADER_COLOR = "`e[1m"
        $env:PO_RESET = "`e[0m"
        try {
            $table = New-PoshUITable -Style Simple -Header Name
            Add-PoshUITableRow -Table $table -Values alpha

            (Format-PoshUITable $table) -join "`n" | Should -Not -Match ([char]27)
        }
        finally {
            $env:PO_TABLE_BORDER_COLOR = ''
            $env:PO_TABLE_HEADER_COLOR = ''
            $env:PO_RESET = ''
        }
    }

    It 'preserves SGR but strips terminal control injection in rich mode' {
        $previousMode = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'rich'
            $table = New-PoshUITable -Style Simple -Header Name
            Add-PoshUITableRow -Table $table -Values "`e[31mred`e[0m`e]52;c;secret`a`e[2J"

            $output = (Format-PoshUITable $table) -join "`n"
            $output | Should -Match "`e\[31mred`e\[0m"
            $output | Should -Not -Match 'secret'
            $output | Should -Not -Match "`e\[2J"
        }
        finally {
            if ($null -eq $previousMode) { Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue }
            else { $env:POSH_UI_MODE = $previousMode }
        }
    }

    It 'routes display through the runtime host boundary' {
        $table = New-PoshUITable -Style Simple -Header Name
        Add-PoshUITableRow -Table $table -Values alpha

        InModuleScope Tables -Parameters @{ TestTable = $table } {
            Mock Write-PoshUIHost
            Show-PoshUITable -Table $TestTable
            Should -Invoke Write-PoshUIHost -Exactly 5
        }
    }
}
