#Requires -Version 7.6

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
}

Describe 'Resolved configuration' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        $script:Module = Import-Module $script:ManifestPath -Force -PassThru
    }

    AfterEach {
        Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'returns stable module-owned defaults' {
        $configuration = Get-PoshUIConfiguration
        $configuration.Progress.Width | Should -Be 50
        $configuration.Table.Style | Should -BeExactly 'standard'
        $configuration.Logging.Level | Should -BeExactly 'INFO'
        $configuration.Theme.Name | Should -BeExactly 'default'
        $configuration.Theme.Semantic.Primary | Should -BeExactly "`e[38;2;0;171;254m"
    }

    It 'does not read legacy PO configuration variables' {
        $env:PO_PROGRESS_BAR_WIDTH = '17'
        try {
            (Get-PoshUIConfiguration).Progress.Width | Should -Be 50
        }
        finally {
            Remove-Item Env:\PO_PROGRESS_BAR_WIDTH -ErrorAction SilentlyContinue
        }
    }

    It 'creates independent primitive semantic and component token layers' {
        $first = New-PoshUITheme -Name dark
        $second = New-PoshUITheme -Name dark
        $first.Semantic.Primary = 'changed'

        $second.Semantic.Primary | Should -BeExactly "`e[0;34m"
        $second.Primitive.Count | Should -BeGreaterThan 0
        $second.Semantic.Count | Should -BeGreaterThan 0
        $second.Component.Table | Should -Not -BeNullOrEmpty
    }

    It 'keeps the aurora theme name as an alias for the default palette' {
        (New-PoshUITheme -Name aurora).Semantic.Primary |
            Should -BeExactly (New-PoshUITheme -Name default).Semantic.Primary
    }

    It 'switches built-in themes for subsequent rich rendering' {
        $env:POSH_UI_MODE = 'rich'
        @(Format-PoshUIBox -Title Status -Content Ready -Width 12)[0] |
            Should -Match ([regex]::Escape("`e[38;2;0;171;254m"))

        Set-PoshUITheme -Name dark

        @(Format-PoshUIBox -Title Status -Content Ready -Width 12)[0] |
            Should -Match ([regex]::Escape("`e[0;34m"))
        (Get-PoshUIConfiguration).Theme.Name | Should -BeExactly 'dark'
    }

    It 'copies a custom theme before activating its component tokens' {
        $env:POSH_UI_MODE = 'rich'
        $theme = New-PoshUITheme -Name default
        $theme.Name = 'custom'
        $theme.Component.Box.Border = "`e[38;2;82;214;255m"
        $theme.Component.Table.Header = "`e[1;38;2;173;232;58m"

        $theme | Set-PoshUITheme
        $theme.Component.Box.Border = 'changed-after-activation'

        (Get-PoshUIConfiguration).Theme.Component.Box.Border |
            Should -BeExactly "`e[38;2;82;214;255m"
        @(Format-PoshUIBox -Content Ready -Width 12)[0] |
            Should -Match ([regex]::Escape("`e[38;2;82;214;255m"))
        $table = New-PoshUITable -Header Name
        Add-PoshUITableRow -Table $table -Values api
        @(Format-PoshUITable -Table $table) -join "`n" |
            Should -Match ([regex]::Escape("`e[1;38;2;173;232;58m"))
    }

    It 'rejects a custom theme with a missing required token' {
        $theme = New-PoshUITheme -Name default
        $theme.Component.Box.Remove('Border')

        { $theme | Set-PoshUITheme } | Should -Throw "*missing required token 'Component.Box.Border'*"
        (Get-PoshUIConfiguration).Theme.Name | Should -BeExactly 'default'
    }

    It 'honors WhatIf without changing the active theme' {
        Set-PoshUITheme -Name dark -WhatIf

        (Get-PoshUIConfiguration).Theme.Name | Should -BeExactly 'default'
    }
}

Describe 'Import environment isolation' {
    It 'restores the complete process environment after import' {
        $before = [Environment]::GetEnvironmentVariables()
        $env:POSH_UI_MODE = 'off'
        $beforeWithMode = [Environment]::GetEnvironmentVariables()
        $module = Import-Module $script:ManifestPath -Force -PassThru
        try {
            $after = [Environment]::GetEnvironmentVariables()
            @($after.Keys | Where-Object { -not $beforeWithMode.Contains($_) }) | Should -BeNullOrEmpty
            @($beforeWithMode.Keys | Where-Object { [string]$after[$_] -cne [string]$beforeWithMode[$_] }) | Should -BeNullOrEmpty
        }
        finally {
            Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
            if ($before.Contains('POSH_UI_MODE')) { $env:POSH_UI_MODE = [string]$before['POSH_UI_MODE'] }
            else { Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue }
        }
    }
}
