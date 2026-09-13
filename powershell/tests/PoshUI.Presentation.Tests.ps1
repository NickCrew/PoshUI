#Requires -Version 7.6

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules')).Path
    $script:IconsPath = Join-Path $script:ModuleRoot 'Icons.psm1'

    function script:Import-PoshUIPresentationMode {
        param([Parameter(Mandatory)][ValidateSet('rich', 'plain', 'off')][string]$Mode)

        Remove-Module Icons, Colors, Runtime -Force -ErrorAction SilentlyContinue
        $env:POSH_UI_MODE = $Mode
        Import-Module $script:IconsPath -Force
    }

    function script:ConvertFrom-PoshUIPresentationAnsi {
        param([AllowEmptyString()][string]$Text)

        [regex]::Replace($Text, "`e\[[0-9;]*m", '')
    }
}

Describe 'Native presentation primitives' {
    AfterEach {
        Remove-Module Icons, Colors, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Module Icons, Colors, Runtime -Force -ErrorAction SilentlyContinue

    }

    It 'formats stable plain headers and subheaders' {
        Import-PoshUIPresentationMode plain

        @(Format-PoshUIHeader -Label RELEASE -Title 'Open releases') |
            Should -Be @('', 'RELEASE Open releases', '')
        Format-PoshUISubheader -Title Summary | Should -BeExactly '▸ Summary'
    }

    It 'formats every semantic status for inline composition' {
        Import-PoshUIPresentationMode plain

        Format-PoshUIStatus Success Ready | Should -BeExactly '✓ Ready'
        Format-PoshUIStatus Error Failed | Should -BeExactly '✗ Failed'
        Format-PoshUIStatus Warning Waiting | Should -BeExactly '⚠ Waiting'
        Format-PoshUIStatus Info Detail | Should -BeExactly 'ℹ Detail'
    }

    It 'preserves visible text while adding rich styling' {
        Import-PoshUIPresentationMode rich

        $header = @(Format-PoshUIHeader TEST 'Rich output')
        $status = Format-PoshUIStatus Success Ready

        ($header -join "`n") | Should -Match "`e\["
        $status | Should -Match "`e\["
        (($header | ForEach-Object { ConvertFrom-PoshUIPresentationAnsi $_ }) -join "`n") |
            Should -Be "`nTEST Rich output`n"
        ConvertFrom-PoshUIPresentationAnsi $status | Should -BeExactly '✓ Ready'
    }

    It 'keeps formatters composable in off mode while displays stay silent' {
        Import-PoshUIPresentationMode off

        Format-PoshUIStatus Info Detail | Should -BeExactly 'ℹ Detail'
        @(Format-PoshUIHeader TEST Results) | Should -Be @('', 'TEST Results', '')
        $output = @(& {
                Show-PoshUIHeader TEST Results
                Show-PoshUISubheader Detail
            } *>&1)
        $output | Should -BeNullOrEmpty
    }

    It 'removes hostile terminal controls from caller text' {
        Import-PoshUIPresentationMode rich
        $hostile = "safe`e]52;c;secret`a`e[2Jvisible$([char]8)"

        $status = Format-PoshUIStatus Warning $hostile

        $status | Should -Not -Match ([regex]::Escape("`e]52"))
        $status | Should -Not -Match ([regex]::Escape("`e[2J"))
        ConvertFrom-PoshUIPresentationAnsi $status | Should -BeExactly '⚠ safevisible'
    }

    It 'rejects invalid or empty semantic input before rendering' {
        Import-PoshUIPresentationMode plain

        { Format-PoshUIStatus Other text } | Should -Throw
        { Format-PoshUIHeader -Label '' -Title Title } | Should -Throw
        { Format-PoshUISubheader -Title '' } | Should -Throw
    }
}
