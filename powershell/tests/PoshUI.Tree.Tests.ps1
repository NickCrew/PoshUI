#Requires -Version 7.6

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'Tree.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'PoshUI tree formatting' {
    BeforeAll { $script:TreeValue = [ordered]@{ Name = 'api'; Services = @('web', 'worker') } }

    It 'formats nested dictionaries and collections in compact ASCII form' {
        @(Format-PoshUITree -InputObject $script:TreeValue -RootLabel Plan -CharacterSet ASCII) | Should -Be @(
            'Plan'
            '|- Name: api'
            '\- Services'
            '   |- [0]: web'
            '   \- [1]: worker'
        )
    }

    It 'formats scalar values as nodes in expanded Unicode form' {
        @(Format-PoshUITree -InputObject $script:TreeValue -RootLabel Plan -Style Expanded) | Should -Be @(
            'Plan'
            '├─ Name'
            '│  └─ api'
            '└─ Services'
            '   ├─ [0]'
            '   │  └─ web'
            '   └─ [1]'
            '      └─ worker'
        )
    }

    It 'makes nulls and depth limits visible' {
        $value = [ordered]@{ Empty = $null; Nested = [ordered]@{ Child = [ordered]@{ Value = 1 } } }
        $actual = @(Format-PoshUITree $value -MaxDepth 1)
        $actual | Should -Contain '├─ Empty: <null>'
        $actual | Should -Contain '   └─ …'
    }

    It 'reports circular references without recursing forever' {
        $value = [pscustomobject]@{ Name = 'root'; Child = $null }
        $value.Child = $value
        @(Format-PoshUITree $value) | Should -Contain '   └─ <circular>'
    }

    It 'renders scalar newlines as indented hierarchy children' {
        $value = [ordered]@{ Notes = "first`nsecond" }
        @(Format-PoshUITree $value -CharacterSet ASCII) | Should -Be @(
            'Root'
            '\- Notes'
            '   |- first'
            '   \- second'
        )
    }

    It 'renders multiline root scalars without leaking raw newlines' {
        @(Format-PoshUITree -InputObject "first`nsecond") | Should -Be @(
            'Root'
            '├─ first'
            '└─ second'
        )
    }

    It 'routes display through the runtime boundary' {
        InModuleScope Tree -Parameters @{ Value = $script:TreeValue } {
            Mock Write-PoshUIHost
            Show-PoshUITree -InputObject $Value -RootLabel Plan
            Should -Invoke Write-PoshUIHost -Exactly 5
        }
    }

    It 'uses the real plain and off host boundaries' {
        $previous = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'plain'
            $plain = @(& { Show-PoshUITree -InputObject ([ordered]@{ Name = 'api' }) } 6>&1)
            ($plain | ForEach-Object { [string]$_ }) | Should -Be @('Root', '└─ Name: api')

            $env:POSH_UI_MODE = 'off'
            @(& { Show-PoshUITree -InputObject ([ordered]@{ Name = 'api' }) } 6>&1) | Should -BeNullOrEmpty
        }
        finally { $env:POSH_UI_MODE = $previous }
    }
}

Describe 'PoshUI tree command contracts' {
    It 'publishes advanced commands with authored help and output metadata' -ForEach @('Format-PoshUITree', 'Show-PoshUITree') {
        $command = Get-Command $_ -Module Tree
        $command.CmdletBinding | Should -BeTrue
        $command.OutputType.Count | Should -BeGreaterThan 0
        (Get-Help $_).Synopsis | Should -Not -BeNullOrEmpty
        @((Get-Help $_).Examples.Example).Count | Should -BeGreaterOrEqual 3
    }
}
