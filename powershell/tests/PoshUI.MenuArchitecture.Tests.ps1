#Requires -Version 7.6

BeforeAll {
    $env:POSH_UI_MODE = 'plain'
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Menus.psm1') -Force
    function global:Test-PoshUIMenuEcho {
        param([Parameter(Mandatory)][object]$Value)
        $Value
    }
}

AfterAll {
    Remove-Module Menus, Icons, Colors, Runtime -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-PoshUIMenuEcho -ErrorAction SilentlyContinue
}

Describe 'Independent menu models' {
    It 'keeps interleaved menu instances isolated' {
        $first = New-PoshUIMenu -Title First
        $second = New-PoshUIMenu -Title Second
        Add-PoshUIMenuItem $first Alpha -Hotkey a
        Add-PoshUIMenuItem $second Beta -Disabled

        $first.Items.Count | Should -Be 1
        $first.Items[0].Label | Should -Be Alpha
        $first.Items[0].Enabled | Should -BeTrue
        $second.Items.Count | Should -Be 1
        $second.Items[0].Label | Should -Be Beta
        $second.Items[0].Enabled | Should -BeFalse
    }

    It 'returns exact composable lines without host output' {
        $menu = New-PoshUIMenu -Title Main
        Add-PoshUIMenuItem $menu Deploy -Hotkey d
        Add-PoshUIMenuItem $menu Retired -Disabled

        $information = @()
        $actual = @(Format-PoshUIMenu $menu -SelectedIndex 1 -InformationVariable information)

        $actual | Should -Be @(
            '╔══════════════════════╗'
            '║ Main                 ║'
            '╠══════════════════════╣'
            '║  [d] Deploy          ║'
            '║> Retired (disabled)  ║'
            '╚══════════════════════╝'
        )
        $information | Should -BeNullOrEmpty
    }

    It 'routes display through the runtime boundary' {
        $menu = New-PoshUIMenu -Title Main
        Add-PoshUIMenuItem $menu Deploy

        InModuleScope Menus -Parameters @{ TestMenu = $menu } {
            Mock Write-PoshUIHost
            Show-PoshUIMenu $TestMenu
            Should -Invoke Write-PoshUIHost -Exactly 5
        }
    }

    It 'invokes scriptblock actions and preserves typed return values' {
        $expected = [pscustomobject]@{ Id = 17 }
        $menu = New-PoshUIMenu -Title Actions
        Add-PoshUIMenuItem $menu Typed -Action { $expected }

        $actual = Invoke-PoshUIMenuAction $menu

        [object]::ReferenceEquals($actual, $expected) | Should -BeTrue
    }

    It 'invokes exact command strings and CommandInfo metadata without evaluation' {
        $menu = New-PoshUIMenu -Title Actions
        Add-PoshUIMenuItem $menu String -Action 'Test-PoshUIMenuEcho'
        Add-PoshUIMenuItem $menu Metadata -Action (Get-Command Test-PoshUIMenuEcho)

        Invoke-PoshUIMenuAction $menu 0 -ArgumentList 42 | Should -Be 42
        Invoke-PoshUIMenuAction $menu 1 -ArgumentList ([uri]'https://example.test') |
            Should -BeOfType ([uri])
    }

    It 'rejects disabled items and command-expression strings' {
        $menu = New-PoshUIMenu -Title Actions
        Add-PoshUIMenuItem $menu Disabled -Action { 'never' } -Disabled
        Add-PoshUIMenuItem $menu Unsafe -Action 'Get-Date;Write-Output'

        { Invoke-PoshUIMenuAction $menu 0 } | Should -Throw '*disabled*'
        { Invoke-PoshUIMenuAction $menu 1 } | Should -Throw '*exact command name*'
    }

    It 'publishes an advanced invocation command with complete authored help' {
        $command = Get-Command Invoke-PoshUIMenuAction

        $command.CmdletBinding | Should -BeTrue
        $command.OutputType.Count | Should -BeGreaterThan 0
        (Get-Help $command.Name).Examples.Example.Count | Should -BeGreaterOrEqual 3
    }
}
