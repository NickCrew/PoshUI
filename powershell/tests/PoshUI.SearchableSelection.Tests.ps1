#Requires -Version 7.6

BeforeAll {
    $script:SearchModulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules' 'SearchableSelection.psm1')).Path
}

Describe 'PoshUI searchable selection models' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module SearchableSelection, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:SearchModulePath -Force

        $script:ProductionValue = [pscustomobject]@{ Id = 7; Name = 'production' }
        $script:Items = @(
            New-PoshUISelectionItem -Label 'Production East' -Value $script:ProductionValue `
                -Preview 'Primary environment' -Keywords api,east
            New-PoshUISelectionItem -Label 'Production West' -Value 9 -Keywords api,west -Disabled
            New-PoshUISelectionItem -Label 'Quality Assurance' -Value ([uri]'https://qa.example.test') `
                -Preview 'Test environment' -Keywords qa,test
            New-PoshUISelectionItem -Label 'Development' -Value 'dev' -Keywords local
        )
    }

    AfterEach {
        Remove-Module SearchableSelection, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'retains typed values and item metadata without conversion' {
        $item = $script:Items[0]

        $item.PSTypeNames | Should -Contain 'PoshUI.SelectionItem'
        [object]::ReferenceEquals($item.Value, $script:ProductionValue) | Should -BeTrue
        $item.Preview | Should -Be 'Primary environment'
        $item.Enabled | Should -BeTrue
        $script:Items[1].Enabled | Should -BeFalse
    }

    It 'filters incrementally across labels and keywords in source order' {
        $production = @($script:Items | Find-PoshUISelectionItem -Query production)
        $eastApi = @(Find-PoshUISelectionItem -Item $script:Items -Query 'EAST api')
        $all = @(Find-PoshUISelectionItem -Item $script:Items -Query '')

        $production.Label | Should -Be @('Production East', 'Production West')
        $production[1].Enabled | Should -BeFalse
        $eastApi.Label | Should -Be @('Production East')
        $all.Label | Should -Be $script:Items.Label
    }

    It 'updates query and filtered state one character at a time' {
        $selection = New-PoshUISearchSelection -Item $script:Items

        foreach ($character in 'q', 'a') {
            Update-PoshUISearchSelection $selection Append -Character $character
        }
        $selection.Query | Should -Be 'qa'
        $selection.FilteredItems.Label | Should -Be @('Quality Assurance')
        $selection.SelectedIndex | Should -Be 0

        Update-PoshUISearchSelection $selection Backspace
        $selection.Query | Should -Be 'q'
        Update-PoshUISearchSelection $selection Reset
        $selection.FilteredItems | Should -HaveCount 4
    }

    It 'wraps keyboard navigation and skips disabled entries' {
        $selection = New-PoshUISearchSelection -Item $script:Items

        $selection.SelectedIndex | Should -Be 0
        Update-PoshUISearchSelection $selection Next
        $selection.SelectedIndex | Should -Be 2
        Update-PoshUISearchSelection $selection Next
        $selection.SelectedIndex | Should -Be 3
        Update-PoshUISearchSelection $selection Next
        $selection.SelectedIndex | Should -Be 0
        Update-PoshUISearchSelection $selection Previous
        $selection.SelectedIndex | Should -Be 3
    }

    It 'does not select when every filtered entry is disabled' {
        $selection = New-PoshUISearchSelection -Item $script:Items
        foreach ($character in 'w', 'e', 's', 't') {
            Update-PoshUISearchSelection $selection Append -Character $character
        }

        $selection.FilteredItems.Label | Should -Be @('Production West')
        $selection.SelectedIndex | Should -Be -1
        Update-PoshUISearchSelection $selection Accept
        $selection.IsAccepted | Should -BeFalse
        $selection.Result | Should -BeNullOrEmpty
    }

    It 'accepts and returns the original typed value' {
        $selection = New-PoshUISearchSelection -Item $script:Items

        Update-PoshUISearchSelection $selection Accept

        $selection.IsAccepted | Should -BeTrue
        [object]::ReferenceEquals($selection.Result, $script:ProductionValue) | Should -BeTrue
    }

    It 'records cancellation without a result' {
        $selection = New-PoshUISearchSelection -Item $script:Items

        Update-PoshUISearchSelection $selection Cancel

        $selection.IsCancelled | Should -BeTrue
        $selection.IsAccepted | Should -BeFalse
        $selection.Result | Should -BeNullOrEmpty
    }

    It 'formats exact choices, disabled state, and optional preview' {
        $selection = New-PoshUISearchSelection -Item $script:Items -Prompt 'Environment'

        $lines = @(Format-PoshUISearchSelection $selection)

        $lines | Should -Be @(
            'Environment'
            'Filter: '
            '> Production East'
            '  Production West (disabled)'
            '  Quality Assurance'
            '  Development'
            'Preview: Primary environment'
        )
        @(Format-PoshUISearchSelection $selection -NoPreview) | Should -HaveCount 6
    }

    It 'formats a stable empty-filter state' {
        $selection = New-PoshUISearchSelection -Item $script:Items
        foreach ($character in 'n', 'o', 'p', 'e') {
            Update-PoshUISearchSelection $selection Append -Character $character
        }

        @(Format-PoshUISearchSelection $selection) | Should -Be @(
            'Select an item'
            'Filter: nope'
            '  No matches'
        )
    }

    It 'strips ANSI in plain mode and preserves it in rich mode' {
        $ansiItems = @(
            New-PoshUISelectionItem -Label "`e[32mReady`e[0m" -Value ready `
                -Preview "`e[36mAvailable`e[0m"
        )
        $selection = New-PoshUISearchSelection -Item $ansiItems

        @(Format-PoshUISearchSelection $selection) | Should -Be @(
            'Select an item'
            'Filter: '
            '> Ready'
            'Preview: Available'
        )

        $env:POSH_UI_MODE = 'rich'
        $rich = @(Format-PoshUISearchSelection $selection)
        $rich[2] | Should -Be "> `e[32mReady`e[0m"
        $rich[3] | Should -Be "Preview: `e[36mAvailable`e[0m"
    }

    It 'provides an exact narrow-width truncation contract' {
        $selection = New-PoshUISearchSelection -Item $script:Items -Prompt 'Choose environment'

        $lines = @(Format-PoshUISearchSelection $selection -Width 12 -Overflow Truncate)

        $lines[0] | Should -Be 'Choose envi…'
        $lines[2] | Should -Be '> Productio…'
        $lines[3] | Should -Be '  Productio…'
        $lines | ForEach-Object { $_.Length | Should -BeLessOrEqual 12 }
    }

    It 'preserves Unicode labels and preview content' {
        $item = New-PoshUISelectionItem -Label 'Café 🚀' -Value 42 -Preview '東京 ready'
        $selection = New-PoshUISearchSelection -Item @($item) -Prompt 'Välj mål'

        @(Format-PoshUISearchSelection $selection) | Should -Be @(
            'Välj mål'
            'Filter: '
            '> Café 🚀'
            'Preview: 東京 ready'
        )
    }

    It 'does not split a narrow ZWJ grapheme' {
        $family = [char]::ConvertFromUtf32(0x1F468) + [char]0x200D +
            [char]::ConvertFromUtf32(0x1F469) + [char]0x200D +
            [char]::ConvertFromUtf32(0x1F467)
        $item = New-PoshUISelectionItem -Label "$family deployment" -Value 42
        $selection = New-PoshUISearchSelection -Item @($item)

        $line = @(Format-PoshUISearchSelection $selection -Width 3 -Overflow Truncate)[2]
        $line | Should -Be '> …'
        $line | Should -Not -Match ([char]0xFFFD)
    }

    It 'keeps two selection models independent' {
        $first = New-PoshUISearchSelection -Item $script:Items -Prompt First
        $second = New-PoshUISearchSelection -Item $script:Items -Prompt Second

        Update-PoshUISearchSelection $first Append -Character q
        Update-PoshUISearchSelection $second Next

        $first.Query | Should -Be q
        $first.SelectedIndex | Should -Be 0
        $second.Query | Should -BeNullOrEmpty
        $second.SelectedIndex | Should -Be 2
    }

    It 'returns immediately without Console reads when input is noninteractive' {
        Mock Read-PoshUISearchKeyInternal { throw 'must not read' } -ModuleName SearchableSelection
        $selection = New-PoshUISearchSelection -Item $script:Items

        $actual = Select-PoshUIItem $selection

        $actual | Should -BeNullOrEmpty
        Should -Invoke Read-PoshUISearchKeyInternal -ModuleName SearchableSelection -Times 0
    }

    It 'accepts typed values in interactive plain mode without cursor control' {
        Mock Get-PoshUIRuntime {
            [pscustomobject]@{ Mode = 'plain'; InteractiveInput = $true }
        } -ModuleName SearchableSelection
        Mock Test-PoshUITerminalControl { $false } -ModuleName SearchableSelection
        Mock Read-PoshUISearchKeyInternal {
            [pscustomobject]@{ Action = 'Accept'; Character = '' }
        } -ModuleName SearchableSelection
        Mock Write-PoshUIHost { } -ModuleName SearchableSelection
        $selection = New-PoshUISearchSelection -Item $script:Items

        $actual = Select-PoshUIItem $selection

        [object]::ReferenceEquals($actual, $script:ProductionValue) | Should -BeTrue
        $selection.IsAccepted | Should -BeTrue
        Should -Invoke Write-PoshUIHost -ModuleName SearchableSelection -Times 7
    }

    It 'restores the rich cursor after acceptance and cancellation' {
        Mock Get-PoshUIRuntime {
            [pscustomobject]@{ Mode = 'rich'; InteractiveInput = $true }
        } -ModuleName SearchableSelection
        Mock Test-PoshUITerminalControl { $true } -ModuleName SearchableSelection
        Mock Write-PoshUISearchFrameInternal { 5 } -ModuleName SearchableSelection
        Mock Write-PoshUISearchCursorVisibilityInternal { } -ModuleName SearchableSelection
        Mock Write-PoshUIHost { } -ModuleName SearchableSelection
        $accept = New-PoshUISearchSelection -Item $script:Items
        $cancel = New-PoshUISearchSelection -Item $script:Items
        $script:NextSearchAction = 'Accept'
        Mock Read-PoshUISearchKeyInternal {
            [pscustomobject]@{ Action = $script:NextSearchAction; Character = '' }
        } -ModuleName SearchableSelection

        $acceptedValue = Select-PoshUIItem $accept
        $script:NextSearchAction = 'Cancel'
        $cancelledValue = Select-PoshUIItem $cancel

        [object]::ReferenceEquals($acceptedValue, $script:ProductionValue) | Should -BeTrue
        $cancelledValue | Should -BeNullOrEmpty
        $cancel.IsCancelled | Should -BeTrue
        Should -Invoke Write-PoshUISearchCursorVisibilityInternal -ModuleName SearchableSelection -Times 2 `
            -ParameterFilter { -not $Visible }
        Should -Invoke Write-PoshUISearchCursorVisibilityInternal -ModuleName SearchableSelection -Times 2 `
            -ParameterFilter { $Visible -and $Force }
    }

    It 'restores the rich cursor when keyboard input fails' {
        Mock Get-PoshUIRuntime {
            [pscustomobject]@{ Mode = 'rich'; InteractiveInput = $true }
        } -ModuleName SearchableSelection
        Mock Test-PoshUITerminalControl { $true } -ModuleName SearchableSelection
        Mock Write-PoshUISearchFrameInternal { 5 } -ModuleName SearchableSelection
        Mock Read-PoshUISearchKeyInternal { throw 'read failed' } -ModuleName SearchableSelection
        Mock Write-PoshUISearchCursorVisibilityInternal { } -ModuleName SearchableSelection
        Mock Write-PoshUIHost { } -ModuleName SearchableSelection
        $selection = New-PoshUISearchSelection -Item $script:Items

        { Select-PoshUIItem $selection } | Should -Throw '*read failed*'

        Should -Invoke Write-PoshUISearchCursorVisibilityInternal -ModuleName SearchableSelection -Times 1 `
            -ParameterFilter { $Visible -and $Force }
    }

    It 'suppresses interaction and output in off mode' {
        Mock Get-PoshUIRuntime {
            [pscustomobject]@{ Mode = 'off'; InteractiveInput = $false }
        } -ModuleName SearchableSelection
        Mock Read-PoshUISearchKeyInternal { throw 'must not read' } -ModuleName SearchableSelection
        Mock Write-PoshUIHost { } -ModuleName SearchableSelection
        $selection = New-PoshUISearchSelection -Item $script:Items

        Select-PoshUIItem $selection | Should -BeNullOrEmpty

        Should -Invoke Read-PoshUISearchKeyInternal -ModuleName SearchableSelection -Times 0
        Should -Invoke Write-PoshUIHost -ModuleName SearchableSelection -Times 0
    }
}

Describe 'Searchable selection public command contracts' {
    BeforeAll {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module SearchableSelection, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:SearchModulePath -Force
    }

    AfterAll {
        Remove-Module SearchableSelection, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'exports only the six supported commands as advanced functions with authored help' {
        $commands = @(Get-Command -Module SearchableSelection)

        $commands.Name | Sort-Object | Should -Be @(
            'Find-PoshUISelectionItem'
            'Format-PoshUISearchSelection'
            'New-PoshUISearchSelection'
            'New-PoshUISelectionItem'
            'Select-PoshUIItem'
            'Update-PoshUISearchSelection'
        )
        foreach ($command in $commands) {
            $command.CmdletBinding | Should -BeTrue -Because $command.Name
            $command.OutputType.Count | Should -BeGreaterThan 0 -Because $command.Name
            (Get-Help $command.Name).Examples.Example.Count | Should -BeGreaterOrEqual 3 -Because $command.Name
        }
    }
}
