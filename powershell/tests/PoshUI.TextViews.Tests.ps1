#Requires -Version 7.6

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'TextViews.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'PoshUI code-block formatting' {
    It 'never exceeds width one for wide graphemes' {
        @(Format-PoshUICodeBlock '部署' -Width 1 -NoLineNumbers) | Should -Be @('…', '…')
    }
    It 'preserves embedded lines and numbers wrapped continuations structurally' {
        @(Format-PoshUICodeBlock -Text "abcdef`nxy" -Width 3) | Should -Be @(
            '1 | abc'
            '  | def'
            '2 | xy'
        )
    }

    It 'accepts pipeline lines and custom starting numbers' {
        @('one', 'two') | Format-PoshUICodeBlock -StartLine 9 | Should -Be @(' 9 | one', '10 | two')
    }

    It 'can omit line numbers without changing source content' {
        @('a|b', 'quoted,c') | Format-PoshUICodeBlock -NoLineNumbers | Should -Be @('a|b', 'quoted,c')
    }

    It 'wraps wide and ZWJ graphemes without splitting them' {
        @(Format-PoshUICodeBlock -Text '部署x' -Width 2 -NoLineNumbers) | Should -Be @('部', '署', 'x')
        @(Format-PoshUICodeBlock -Text '👨‍👩‍👧‍👦x' -Width 2 -NoLineNumbers) | Should -Be @('👨‍👩‍👧‍👦', 'x')
        @(Format-PoshUICodeBlock -Text "e$([char]0x0301)x" -Width 1 -NoLineNumbers) | Should -Be @("e$([char]0x0301)", 'x')
    }

    It 'balances ANSI styles at wrap boundaries and strips them in plain mode' {
        $previous = $env:POSH_UI_MODE
        try {
            $colored = "`e[31mabcdef`e[0m"
            $env:POSH_UI_MODE = 'rich'
            @(Format-PoshUICodeBlock -Text $colored -Width 3 -NoLineNumbers) | Should -Be @(
                "`e[31mabc`e[0m"
                "`e[31mdef`e[0m"
            )

            $env:POSH_UI_MODE = 'plain'
            @(Format-PoshUICodeBlock -Text $colored -Width 3 -NoLineNumbers) | Should -Be @('abc', 'def')
        }
        finally { $env:POSH_UI_MODE = $previous }
    }
}

Describe 'PoshUI diff formatting' {
    It 'marks removals additions and context independently of color' {
        @(Format-PoshUIDiff -OldText @('one', 'old', 'same') -NewText @('one', 'new', 'same') -ContextLines 1) | Should -Be @(
            '  1 1 | one'
            '- 2   | old'
            '+   2 | new'
            '  3 3 | same'
        )
    }

    It 'collapses distant context with a stable marker' {
        $old = @('a', 'b', 'c', 'd', 'old', 'f', 'g', 'h')
        $new = @('a', 'b', 'c', 'd', 'new', 'f', 'g', 'h')
        $actual = @(Format-PoshUIDiff -OldText $old -NewText $new -ContextLines 1 -NoLineNumbers)
        $actual | Should -Be @('...', '  d', '- old', '+ new', '  f', '...')
    }

    It 'retains state markers on wrapped continuations' {
        @(Format-PoshUIDiff -OldText 'abcdef' -NewText 'uvwxyz' -Width 3 -NoLineNumbers) | Should -Be @(
            '- abc', '- def', '+ uvw', '+ xyz'
        )
    }

    It 'preserves Unicode and ANSI boundaries in diff content' {
        $previous = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'rich'
            $actual = @(Format-PoshUIDiff -OldText "`e[31m👨‍👩‍👧‍👦x`e[0m" -NewText 'ok' -Width 2 -NoLineNumbers)
            $actual[0] | Should -Be "- `e[31m👨‍👩‍👧‍👦`e[0m"
            $actual[1] | Should -Be "- `e[31mx`e[0m"
            $actual[2] | Should -Be '+ ok'
        }
        finally { $env:POSH_UI_MODE = $previous }
    }

    It 'routes both display wrappers through the runtime boundary' {
        InModuleScope TextViews {
            Mock Write-PoshUIHost
            Show-PoshUICodeBlock -Text 'one'
            Show-PoshUIDiff -OldText 'old' -NewText 'new'
            Should -Invoke Write-PoshUIHost -Exactly 3
        }
    }

    It 'uses the real plain and off Show boundaries' {
        $previous = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'plain'
            $plain = @(& { Show-PoshUICodeBlock -Text 'one' } 6>&1 | ForEach-Object { [string]$_ })
            $plain | Should -Be @('1 | one')

            $env:POSH_UI_MODE = 'off'
            @(& { Show-PoshUIDiff -OldText 'old' -NewText 'new' } 6>&1) | Should -BeNullOrEmpty
        }
        finally { $env:POSH_UI_MODE = $previous }
    }
}

Describe 'PoshUI text-view command contracts' {
    It 'publishes advanced commands with authored help and output metadata' -ForEach @(
        'Format-PoshUICodeBlock', 'Show-PoshUICodeBlock', 'Format-PoshUIDiff', 'Show-PoshUIDiff'
    ) {
        $command = Get-Command $_ -Module TextViews
        $command.CmdletBinding | Should -BeTrue
        $command.OutputType.Count | Should -BeGreaterThan 0
        (Get-Help $_).Synopsis | Should -Not -BeNullOrEmpty
        @((Get-Help $_).Examples.Example).Count | Should -BeGreaterOrEqual 3
    }
}
