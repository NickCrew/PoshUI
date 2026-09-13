#Requires -Version 7.6

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
    $script:RuntimePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules' 'Runtime.psm1')).Path
}

Describe 'PoshUI runtime modes' {
    AfterEach {
        Get-Module -All PoshUI, Runtime | Remove-Module -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'suppresses display and file effects in off mode without removing commands' {
        $env:POSH_UI_MODE = 'off'
        $module = Import-Module $script:ManifestPath -Force -PassThru
        $path = Join-Path $TestDrive 'off.jsonl'
        Set-PoshUILogConfiguration -FilePath $path -ConsoleOutput $true

        $captured = @(& {
            Show-PoshUIBox -Title Hidden -Content Hidden
            Write-PoshUILog -Level Error -Message Hidden
        } *>&1)

        $captured | Should -BeNullOrEmpty
        Test-Path $path | Should -BeFalse
        $module.ExportedCommands.ContainsKey('Show-PoshUIBox') | Should -BeTrue
    }

    It 'renders stable ANSI-free text in plain mode' {
        $env:POSH_UI_MODE = 'plain'
        Import-Module $script:ManifestPath -Force
        $text = @(Format-PoshUIBox -Title Plain -Content Readable) -join "`n"

        $text | Should -Match 'Plain'
        $text | Should -Not -Match "`e\["
    }

    It 'uses plain mode automatically in CI' {
        $previous = $env:CI
        try {
            Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
            $env:CI = 'true'
            Import-Module $script:RuntimePath -Force
            (Get-PoshUIRuntime).Mode | Should -BeExactly 'plain'
            (Get-PoshUIRuntime).InteractiveInput | Should -BeFalse
        }
        finally {
            if ($null -eq $previous) { Remove-Item Env:\CI -ErrorAction SilentlyContinue }
            else { $env:CI = $previous }
        }
    }

    It 'exports a typed runtime diagnostic from the root module' {
        $env:POSH_UI_MODE = 'off'
        $module = Import-Module $script:ManifestPath -Force -PassThru

        $runtime = Get-PoshUIRuntime

        $module.ExportedCommands.ContainsKey('Get-PoshUIRuntime') | Should -BeTrue
        $runtime.PSObject.TypeNames | Should -Contain 'PoshUI.Runtime'
        $runtime.Mode | Should -BeExactly 'off'
        $runtime.Reason | Should -BeExactly 'explicit'
        $runtime.InteractiveInput | Should -BeFalse
        $runtime.TerminalControl | Should -BeFalse
    }

    It 'honors explicit rich mode' {
        $env:POSH_UI_MODE = 'rich'
        Import-Module $script:ManifestPath -Force
        Format-PoshUIStatus Success Ready | Should -Match "`e\["
    }

    It 'applies runtime mode changes after the module is imported' {
        $env:POSH_UI_MODE = 'plain'
        Import-Module $script:ManifestPath -Force
        Format-PoshUIStatus Success Ready | Should -Not -Match "`e\["

        $env:POSH_UI_MODE = 'rich'
        Format-PoshUIStatus Success Ready | Should -Match "`e\["

        $env:POSH_UI_MODE = 'plain'
        Format-PoshUIStatus Success Ready | Should -Not -Match "`e\["
    }

    It 'warns once and falls back for an invalid mode' {
        $env:POSH_UI_MODE = 'invalid'
        Import-Module $script:RuntimePath -Force
        $result = @(& { Get-PoshUIRuntime } 3>&1)
        @($result | Where-Object { $_ -is [Management.Automation.WarningRecord] }) | Should -HaveCount 1
        @($result | Where-Object { $_ -isnot [Management.Automation.WarningRecord] })[0].Mode |
            Should -BeIn @('plain', 'rich')
    }
}

Describe 'Runtime terminal safety and cursor coordination' {
    BeforeEach {
        $env:POSH_UI_MODE = 'rich'
        Get-Module -All Runtime | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $script:RuntimePath -Force
    }

    AfterEach {
        Get-Module -All Runtime | Remove-Module -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'strips terminal controls from plain text' {
        ConvertTo-PoshUIPlainText "before`e]52;c;secret`a`e[2Jafter" | Should -BeExactly 'beforeafter'
    }

    It 'preserves only SGR sequences in safe rich text' {
        $safe = ConvertTo-PoshUISafeRichText "`e[31mred`e[0m`e[2J`e[?1m"
        $safe | Should -Match "`e\[31m"
        $safe | Should -Not -Match "`e\[2J"
        $safe | Should -Not -Match "`e\[\?1m"
    }

    It 'sanitizes rich host output while preserving trusted cursor controls' {
        $original = [Console]::Out
        $writer = [IO.StringWriter]::new()
        try {
            [Console]::SetOut($writer)
            Write-PoshUIHost "`e[31mred`e[0m`e]52;c;secret`a`e[2J"
            Write-PoshUIHost "`e[2K" -NoNewline -TrustedControl
        }
        finally {
            [Console]::SetOut($original)
        }

        $output = $writer.ToString()
        $output | Should -Match "`e\[31mred`e\[0m"
        $output | Should -Not -Match 'secret'
        ([regex]::Matches($output, "`e\[2[JK]")).Count | Should -Be 1
    }

    It 'rejects a second cursor owner and releases the first' {
        $first = [guid]::NewGuid()
        $second = [guid]::NewGuid()
        Enter-PoshUICursorLease -OwnerId $first
        { Enter-PoshUICursorLease -OwnerId $second } | Should -Throw '*owns the terminal cursor*'
        Exit-PoshUICursorLease -OwnerId $first
        { Enter-PoshUICursorLease -OwnerId $second } | Should -Not -Throw
        Exit-PoshUICursorLease -OwnerId $second
    }
}
