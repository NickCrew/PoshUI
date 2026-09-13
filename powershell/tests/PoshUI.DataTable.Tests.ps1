#Requires -Version 7.6

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'DataTable.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'PoshUI object data table' {
    It 'accepts pipeline objects and selected properties in caller order' {
        $actual = @(
            @(
                [pscustomobject]@{ Score = 7; Name = 'Ada' }
                [pscustomobject]@{ Score = 12; Name = 'Grace' }
            ) | Format-PoshUIDataTable -Property Name, Score
        )
        $actual | Should -Be @(
            '+-------+-------+'
            '| Name  | Score |'
            '+-------+-------+'
            '| Ada   | 7     |'
            '| Grace | 12    |'
            '+-------+-------+'
        )
    }

    It 'preserves delimiters and embedded newlines as structured cell data' {
        $notes = New-PoshUIDataColumn -Property Notes -MaxWidth 5 -Overflow Wrap
        $actual = @(
            [pscustomobject]@{ Name = 'svc'; Notes = "a|b`nquoted,c" } |
                Format-PoshUIDataTable -Property Name, $notes
        )
        $actual | Should -Be @(
            '+------+-------+'
            '| Name | Notes |'
            '+------+-------+'
            '| svc  | a|b   |'
            '|      | quote |'
            '|      | d,c   |'
            '+------+-------+'
        )
    }

    It 'applies per-column formatters, truncation, and alignment' {
        $score = New-PoshUIDataColumn -Property Score -Name Total -Formatter { param($value) "[$value]" } -Alignment Right
        $note = New-PoshUIDataColumn -Property Note -MaxWidth 4 -Overflow Truncate
        $actual = @([pscustomobject]@{ Score = 7; Note = 'abcdef' } | Format-PoshUIDataTable -Property $score, $note)
        $actual[3] | Should -Be '|   [7] | abc… |'
    }

    It 'enforces maximum width on headers and wide Unicode cells' {
        $column = New-PoshUIDataColumn -Property Value -Name VeryLongHeader -MaxWidth 4
        $actual = @([pscustomobject]@{ Value = '部署A' } | Format-PoshUIDataTable -Property $column)
        $actual | Should -Be @(
            '+------+'
            '| Ver… |'
            '+------+'
            '| 部…  |'
            '+------+'
        )
    }

    It 'wraps a ZWJ grapheme without splitting its code points' {
        $column = New-PoshUIDataColumn -Property Value -Name V -MaxWidth 2 -Overflow Wrap
        $actual = @([pscustomobject]@{ Value = '👨‍👩‍👧‍👦x' } | Format-PoshUIDataTable -Property $column)
        $actual | Should -Be @(
            '+----+'
            '| V  |'
            '+----+'
            '| 👨‍👩‍👧‍👦 |'
            '| x  |'
            '+----+'
        )
    }

    It 'sorts before returning a bounded page' {
        $actual = @(
            @(
                [pscustomobject]@{ Name = 'c'; Score = 3 }
                [pscustomobject]@{ Name = 'a'; Score = 1 }
                [pscustomobject]@{ Name = 'b'; Score = 2 }
            ) | Format-PoshUIDataTable -Property Name -SortBy Score -Descending -Page 2 -PageSize 1
        )
        $actual | Should -Be @(
            '+------+'
            '| Name |'
            '+------+'
            '| b    |'
            '+------+'
            '[Page 2 of 3, 3 rows]'
        )
    }

    It 'rejects pages outside the sorted result set' {
        { [pscustomobject]@{ Name = 'a' } | Format-PoshUIDataTable -Page 2 -PageSize 1 } |
            Should -Throw '*exceeds the available page count*'
    }

    It 'routes display through the runtime boundary' {
        InModuleScope DataTable {
            Mock Write-PoshUIHost
            [pscustomobject]@{ Name = 'a' } | Show-PoshUIDataTable -Property Name
            Should -Invoke Write-PoshUIHost -Exactly 5
        }
    }

    It 'uses the real plain and off host boundaries' {
        $previous = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'plain'
            $plain = @(& { [pscustomobject]@{ Name = 'a' } | Show-PoshUIDataTable -Property Name } 6>&1)
            $plain.Count | Should -Be 5
            ($plain | ForEach-Object { [string]$_ })[3] | Should -Be '| a    |'

            $env:POSH_UI_MODE = 'off'
            @(& { [pscustomobject]@{ Name = 'a' } | Show-PoshUIDataTable -Property Name } 6>&1) | Should -BeNullOrEmpty
        }
        finally { $env:POSH_UI_MODE = $previous }
    }

    It 'preserves ANSI only in rich formatting while retaining table width' {
        $previous = $env:POSH_UI_MODE
        try {
            $column = New-PoshUIDataColumn -Property Value -MaxWidth 4 -Formatter { param($value) "`e[31m$value`e[0m" }
            $env:POSH_UI_MODE = 'rich'
            $rich = @([pscustomobject]@{ Value = '部署' } | Format-PoshUIDataTable -Property $column)
            $rich[3] | Should -Match ([char]27)
            ([regex]::Replace($rich[3], "`e\[[0-9;?]*[ -/]*[@-~]", '')) | Should -Be '| 部署 |'

            $env:POSH_UI_MODE = 'plain'
            ([pscustomobject]@{ Value = '部署' } | Format-PoshUIDataTable -Property $column)[3] | Should -Not -Match ([char]27)
        }
        finally { $env:POSH_UI_MODE = $previous }
    }
}

Describe 'PoshUI data table command contracts' {
    It 'publishes advanced commands with authored help and output metadata' -ForEach @(
        'New-PoshUIDataColumn', 'Format-PoshUIDataTable', 'Show-PoshUIDataTable'
    ) {
        $command = Get-Command $_ -Module DataTable
        $command.CmdletBinding | Should -BeTrue
        $command.OutputType.Count | Should -BeGreaterThan 0
        (Get-Help $_).Synopsis | Should -Not -BeNullOrEmpty
        @((Get-Help $_).Examples.Example).Count | Should -BeGreaterOrEqual 3
    }
}
