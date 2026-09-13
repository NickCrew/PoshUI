#Requires -Version 7.6

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules')).Path
    $script:LayoutPath = Join-Path $script:ModuleRoot 'Layout.psm1'
    $script:BoxesPath = Join-Path $script:ModuleRoot 'Boxes.psm1'
    $script:ExpectedLayoutCommands = @(
        'Format-PoshUIText'
        'Format-PoshUIPanel'
        'Show-PoshUIPanel'
        'Format-PoshUIStack'
        'Show-PoshUIStack'
        'Format-PoshUIColumn'
        'Show-PoshUIColumn'
        'Format-PoshUIGrid'
        'Show-PoshUIGrid'
    )
}

Describe 'Layout public contracts' {
    BeforeAll {
        $env:POSH_UI_MODE = 'plain'
        Import-Module $script:LayoutPath -Force
    }

    AfterAll {
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'exports only the supported layout commands' {
        @(Get-Command -Module Layout | Select-Object -ExpandProperty Name | Sort-Object) |
            Should -Be @($script:ExpectedLayoutCommands | Sort-Object)
    }

    It 'publishes advanced functions with output metadata and three examples' {
        foreach ($name in $script:ExpectedLayoutCommands) {
            $command = Get-Command -Name $name -Module Layout
            $command.CmdletBinding | Should -BeTrue -Because "$name must be an advanced function"
            @($command.OutputType) | Should -Not -BeNullOrEmpty -Because "$name must declare output metadata"
            @((Get-Help -Name $name -Full).Examples.Example) |
                Should -HaveCount 3 -Because "$name must document three usage shapes"
        }
    }
}

Describe 'Terminal-width-aware text layout' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LayoutPath -Force
    }

    AfterEach {
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'wraps at word boundaries with exact fixed-width lines' {
        @(Format-PoshUIText 'alpha beta gamma' -Width 10 -Overflow Wrap) | Should -Be @(
            'alpha beta'
            'gamma     '
        )
    }

    It 'applies padding and center alignment exactly' {
        @(Format-PoshUIText 'ok' -Width 8 -PaddingLeft 1 -PaddingRight 1 -PaddingTop 1 -PaddingBottom 1 -HorizontalAlignment Center) |
            Should -Be @(
                '        '
                '   ok   '
                '        '
            )
    }

    It 'truncates Unicode by display columns instead of UTF-16 length' {
        Format-PoshUIText '部署ready' -Width 6 -Overflow Truncate |
            Should -BeExactly '部署r…'
    }

    It 'wraps a ZWJ family emoji as one two-column grapheme' {
        @(Format-PoshUIText '👨‍👩‍👧‍👦x' -Width 2 -Overflow Wrap) |
            Should -Be @('👨‍👩‍👧‍👦', 'x ')
    }

    It 'truncates without splitting a ZWJ family emoji' {
        Format-PoshUIText '👨‍👩‍👧‍👦ab' -Width 3 -Overflow Truncate |
            Should -BeExactly '👨‍👩‍👧‍👦…'
    }

    It 'keeps combining sequences intact while wrapping' {
        @(Format-PoshUIText "e$([char]0x0301)x" -Width 1 -Overflow Wrap) |
            Should -Be @("e$([char]0x0301)", 'x')
    }

    It 'handles the narrowest valid width' {
        @(Format-PoshUIText 'abc' -Width 1 -Overflow Wrap) | Should -Be @('a', 'b', 'c')
    }

    It 'replaces graphemes wider than the narrowest width without overflow' {
        @(Format-PoshUIText '部署' -Width 1 -Overflow Wrap) | Should -Be @('…', '…')
    }

    It 'rejects padding that leaves no content column' {
        { Format-PoshUIText 'x' -Width 2 -PaddingLeft 1 -PaddingRight 1 } |
            Should -Throw '*at least 3 columns*'
    }

    It 'resolves zero width from the terminal with a safe fallback' {
        $expected = try { [Console]::WindowWidth } catch { 80 }
        if ($expected -lt 1) { $expected = 80 }
        (Format-PoshUIText 'x' -Width 0).Length | Should -Be $expected
    }
}

Describe 'Panel layout' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Boxes, Layout, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LayoutPath -Force
    }

    AfterEach {
        Remove-Module Boxes, Layout, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'returns an exact rounded panel without host output' {
        $information = [System.Collections.Generic.List[object]]::new()
        $actual = @(Format-PoshUIPanel -Title Status -InputObject Ready -Width 16 -InformationVariable information)

        $actual | Should -Be @(
            '╭ Status ──────╮'
            '│ Ready        │'
            '╰──────────────╯'
        )
        $information | Should -BeNullOrEmpty
    }

    It 'wraps multiple direct input lines inside an ASCII panel' {
        @(Format-PoshUIPanel -InputObject @('alpha beta', 'done') -Width 10 -Padding 1 -BorderStyle Ascii) |
            Should -Be @(
                '+--------+'
                '| alpha  |'
                '| beta   |'
                '| done   |'
                '+--------+'
            )
    }

    It 'accepts exact formatted lines from another component' {
        Import-Module $script:BoxesPath -Force
        $box = @(Format-PoshUIBox -Content 'ok' -Width 8)

        @(Format-PoshUIPanel -InputObject $box -Width 12 -Padding 1 -BorderStyle Ascii) |
            Should -Be @(
                '+----------+'
                '| ╔══════╗ |'
                '| ║ ok   ║ |'
                '| ╚══════╝ |'
                '+----------+'
            )
    }
}

Describe 'Stack, column, and grid composition' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LayoutPath -Force
    }

    AfterEach {
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'formats a vertical stack with a stable gap' {
        @(Format-PoshUIStack -Block @('one', 'two') -Width 6 -Gap 1) |
            Should -Be @('one   ', '      ', 'two   ')
    }

    It 'keeps multi-line columns aligned to the tallest component' {
        $columns = [object[]]::new(2)
        $columns[0] = [string[]]@('A1', 'A2')
        $columns[1] = [string[]]@('B1')
        @(Format-PoshUIColumn -Column $columns -Width 9 -Gap 1) |
            Should -Be @('A1   B1  ', 'A2       ')
    }

    It 'allocates remainder columns from left to right' {
        Format-PoshUIColumn -Column @('left', 'right') -Width 11 -Gap 1 |
            Should -BeExactly 'left  right'
    }

    It 'rejects explicit column widths that do not fit the layout' {
        { Format-PoshUIColumn -Column @('a', 'b') -Width 10 -Gap 1 -ColumnWidth 4, 4 } |
            Should -Throw '*must total 9*'
    }

    It 'formats an incomplete grid with exact row and column gaps' {
        @(Format-PoshUIGrid -Cell @('a', 'b', 'c') -Columns 2 -Width 9 -ColumnGap 1 -RowGap 1) |
            Should -Be @('a    b   ', '         ', 'c        ')
    }

    It 'rejects a grid narrower than its cells and gaps' {
        { Format-PoshUIGrid -Cell @('a', 'b') -Columns 2 -Width 2 -ColumnGap 1 } |
            Should -Throw '*at least 3 columns*'
    }
}

Describe 'Layout Runtime boundary' {
    AfterEach {
        Remove-Module Layout, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'preserves ANSI in rich formatting and strips it in plain formatting' {
        $colored = "`e[31mred`e[0m"
        $env:POSH_UI_MODE = 'rich'
        Import-Module $script:LayoutPath -Force
        Format-PoshUIText $colored -Width 4 | Should -Match ([char]27)

        Remove-Module Layout, Runtime -Force
        $env:POSH_UI_MODE = 'plain'
        Import-Module $script:LayoutPath -Force
        Format-PoshUIText $colored -Width 4 | Should -BeExactly 'red '
    }

    It 'preserves ANSI styling through truncation and resets it afterward' {
        $env:POSH_UI_MODE = 'rich'
        Import-Module $script:LayoutPath -Force

        Format-PoshUIText "`e[31mabcdef`e[0m" -Width 4 -Overflow Truncate |
            Should -BeExactly "`e[31mabc…`e[0m"
    }

    It 'removes complete controls before wrapping can expose their payload' {
        $env:POSH_UI_MODE = 'rich'
        Import-Module $script:LayoutPath -Force

        $output = @(Format-PoshUIText "before`e]52;c;secret`aafter" -Width 8 -Overflow Wrap) -join "`n"
        $output | Should -Not -Match 'secret|52;c'
        ($output -replace '\s', '') | Should -Match 'beforeafter'
    }

    It 'makes Show output match the formatter through the information stream' {
        $env:POSH_UI_MODE = 'plain'
        Import-Module $script:LayoutPath -Force
        $shown = @(& { Show-PoshUIPanel Ready -Title Status -Width 16 } 6>&1 | ForEach-Object MessageData)

        $shown | Should -Be @(Format-PoshUIPanel Ready -Title Status -Width 16)
    }

    It 'produces no display effect in off mode' {
        $env:POSH_UI_MODE = 'off'
        Import-Module $script:LayoutPath -Force

        @(& { Show-PoshUIGrid -Cell @('a', 'b') -Columns 2 -Width 9 } 6>&1) |
            Should -BeNullOrEmpty
    }
}
