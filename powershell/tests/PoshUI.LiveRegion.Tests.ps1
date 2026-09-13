#Requires -Version 7.6

BeforeAll {
    $script:LiveRegionModulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules' 'LiveRegion.psm1')).Path
}

Describe 'PoshUI live display region' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module LiveRegion, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LiveRegionModulePath -Force
    }

    AfterEach {
        Remove-Module LiveRegion, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'creates typed independent models with independently keyed semantic content' {
        $first = New-PoshUILiveRegion -Name first -Title 'First'
        $second = New-PoshUILiveRegion -Name second

        Set-PoshUILiveRegionContent $first build '10%' -Kind Progress
        Set-PoshUILiveRegionContent $first worker '|' -Kind Spinner
        Set-PoshUILiveRegionContent $second jobs 'Jobs: 3' -Kind Dashboard
        Set-PoshUILiveRegionContent $first build '20%' -Kind Progress

        $first.PSTypeNames | Should -Contain 'PoshUI.LiveRegion'
        @($first.Entries.Keys) | Should -Be @('build', 'worker')
        $first.Entries.build.Content | Should -Be @('20%')
        $first.Entries.worker.Kind | Should -Be 'Spinner'
        @($second.Entries.Keys) | Should -Be @('jobs')
    }

    It 'formats stable insertion-ordered plain content without consuming messages' {
        $region = New-PoshUILiveRegion -Name status -Title "`e[1mStatus`e[0m"
        Set-PoshUILiveRegionContent $region progress @('Build 50%', 'Tests 25%') -Kind Progress
        Set-PoshUILiveRegionContent $region log 'Ready' -Kind Log
        Add-PoshUILiveRegionMessage $region "`e[32mStarted`e[0m"

        $lines = @(Format-PoshUILiveRegion $region -IncludeMessages)

        $lines | Should -Be @('Started', 'Status', 'Build 50%', 'Tests 25%', 'Ready')
        $region.PendingMessages | Should -HaveCount 1
        $region.IsOpen | Should -BeFalse
    }

    It 'preserves ANSI content in explicit rich mode' {
        $env:POSH_UI_MODE = 'rich'
        $region = New-PoshUILiveRegion -Name rich -Title "`e[1mStatus`e[0m"
        Set-PoshUILiveRegionContent $region job "`e[32mReady`e[0m"
        Add-PoshUILiveRegionMessage $region "`e[36mStarted`e[0m"

        @(Format-PoshUILiveRegion $region -IncludeMessages) | Should -Be @(
            "`e[36mStarted`e[0m"
            "`e[1mStatus`e[0m"
            "`e[32mReady`e[0m"
        )
    }

    It 'allows SGR styling but strips cursor, OSC, and control injection in rich mode' {
        $env:POSH_UI_MODE = 'rich'
        $region = New-PoshUILiveRegion -Name safe
        $hostile = "`e]52;c;secret`a`e[2J`e[31mReady`e[0m$([char]8)"
        Set-PoshUILiveRegionContent $region job $hostile

        @(Format-PoshUILiveRegion $region) | Should -Be @("`e[31mReady`e[0m")
    }

    It 'splits embedded newlines and reclamps content after terminal resize' {
        Mock Get-PoshUILiveTerminalWidthInternal { 5 } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name resized -Width 20
        Set-PoshUILiveRegionContent $region job "abcdef`ngh"

        @(Format-PoshUILiveRegion $region) | Should -Be @('abcde', 'f', 'gh')
    }

    It 'emits an exact append-only plain transcript and writes pending messages once' {
        $region = New-PoshUILiveRegion -Name build -Title Build
        Set-PoshUILiveRegionContent $region progress '10%' -Kind Progress
        Add-PoshUILiveRegionMessage $region 'Started'

        $first = @(& { Show-PoshUILiveRegion $region } 6>&1 | ForEach-Object { [string]$_ })
        Set-PoshUILiveRegionContent $region progress '20%' -Kind Progress
        $second = @(& { Show-PoshUILiveRegion $region } 6>&1 | ForEach-Object { [string]$_ })

        $first | Should -Be @('Started', 'Build', '10%')
        $second | Should -Be @('Build', '20%')
        $region.PendingMessages | Should -HaveCount 0
    }

    It 'suppresses all display effects in off mode' {
        $env:POSH_UI_MODE = 'off'
        $region = New-PoshUILiveRegion -Name quiet
        Set-PoshUILiveRegionContent $region job 'Running'

        $actual = @(& { Show-PoshUILiveRegion $region } 6>&1)

        $actual | Should -HaveCount 0
        $region.IsOpen | Should -BeFalse
        $region.OwnsCursor | Should -BeFalse
    }

    It 'does not publish region state through environment variables' {
        $before = @{}
        Get-ChildItem Env: | ForEach-Object { $before[$_.Name] = $_.Value }

        $region = New-PoshUILiveRegion -Name isolated
        Set-PoshUILiveRegionContent $region job 'Running'
        $null = Format-PoshUILiveRegion $region

        $after = @{}
        Get-ChildItem Env: | ForEach-Object { $after[$_.Name] = $_.Value }
        $after.Count | Should -Be $before.Count
        foreach ($key in $before.Keys) { $after[$key] | Should -Be $before[$key] }
    }

    It 'allows only one rich cursor owner at a time' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveControlInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $first = New-PoshUILiveRegion -Name first
        $second = New-PoshUILiveRegion -Name second
        Set-PoshUILiveRegionContent $first one 'First'
        Set-PoshUILiveRegionContent $second two 'Second'

        Show-PoshUILiveRegion $first
        { Show-PoshUILiveRegion $second } | Should -Throw '*owns the terminal cursor*'

        $first.OwnsCursor | Should -BeTrue
        $second.IsClosed | Should -BeTrue
        Close-PoshUILiveRegion $first
    }

    It 'defers non-owner output and emits it above the next rich snapshot' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveRichSnapshotInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name coordinated
        Set-PoshUILiveRegionContent $region job 'Running'

        Show-PoshUILiveRegion $region
        InModuleScope LiveRegion { Write-PoshUIHost 'Background log' }
        Show-PoshUILiveRegion $region

        Should -Invoke Write-PoshUILiveRichSnapshotInternal -ModuleName LiveRegion -Times 1 `
            -ParameterFilter { $Messages -contains 'Background log' }
        Close-PoshUILiveRegion $region
    }

    It 'restores cursor ownership after successful work' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveControlInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name success
        Set-PoshUILiveRegionContent $region job 'Running'

        $actual = Invoke-PoshUILiveRegion $region {
            param($live)
            Show-PoshUILiveRegion $live
            'done'
        }

        $actual | Should -Be 'done'
        $region.IsClosed | Should -BeTrue
        $region.OwnsCursor | Should -BeFalse
        Should -Invoke Write-PoshUILiveCursorVisibilityInternal -ModuleName LiveRegion -Times 1 -ParameterFilter { -not $Visible }
        Should -Invoke Write-PoshUILiveCursorVisibilityInternal -ModuleName LiveRegion -Times 1 -ParameterFilter { $Visible }
    }

    It 'restores cursor ownership after an exception' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveControlInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name failure
        Set-PoshUILiveRegionContent $region job 'Running'

        {
            Invoke-PoshUILiveRegion $region {
                param($live)
                Show-PoshUILiveRegion $live
                throw 'failed'
            }
        } | Should -Throw '*failed*'

        $region.IsClosed | Should -BeTrue
        $region.OwnsCursor | Should -BeFalse
        Should -Invoke Write-PoshUILiveCursorVisibilityInternal -ModuleName LiveRegion -Times 1 -ParameterFilter { $Visible }
    }

    It 'restores cursor ownership after cancellation' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveControlInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name cancelled
        Set-PoshUILiveRegionContent $region job 'Running'

        {
            Invoke-PoshUILiveRegion $region {
                param($live)
                Show-PoshUILiveRegion $live
                throw [System.OperationCanceledException]::new('cancelled')
            }
        } | Should -Throw -ExceptionType ([System.OperationCanceledException])

        $region.IsClosed | Should -BeTrue
        $region.CursorHidden | Should -BeFalse
        Should -Invoke Write-PoshUILiveCursorVisibilityInternal -ModuleName LiveRegion -Times 1 -ParameterFilter { $Visible }
    }

    It 'releases ownership and flags even when cursor restoration throws' {
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveControlInternal { } -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal { } -ModuleName LiveRegion
        $region = New-PoshUILiveRegion -Name restore
        Set-PoshUILiveRegionContent $region job 'Running'
        Show-PoshUILiveRegion $region
        Mock Write-PoshUILiveCursorVisibilityInternal { throw 'cursor restore failed' } `
            -ModuleName LiveRegion -ParameterFilter { $Visible }

        { Close-PoshUILiveRegion $region } | Should -Throw '*cursor restore failed*'

        $region.IsClosed | Should -BeTrue
        $region.IsOpen | Should -BeFalse
        $region.OwnsCursor | Should -BeFalse
        $region.CursorHidden | Should -BeFalse
        $region.RenderedLineCount | Should -Be 0

        $next = New-PoshUILiveRegion -Name next
        Set-PoshUILiveRegionContent $next job 'Ready'
        { Show-PoshUILiveRegion $next } | Should -Not -Throw
        $next.OwnsCursor | Should -BeTrue
        $next.CursorHidden = $false
        Close-PoshUILiveRegion $next
    }

    It 'emits exact VT operations when a rich snapshot shrinks' {
        $region = New-PoshUILiveRegion -Name shrink
        $region.RenderedLineCount = 3

        $actual = InModuleScope LiveRegion -Parameters @{ TestRegion = $region } {
            Mock Write-PoshUILiveControlInternal { $Text }
            @(Write-PoshUILiveRichSnapshotInternal -Region $TestRegion -Messages @() -Lines @('Only'))
        }

        $actual | Should -Be @(
            "`e[3A"
            "`e[2KOnly`n"
            "`e[2K`n"
            "`e[2K`n"
            "`e[2A"
        )
        $region.RenderedLineCount | Should -Be 1
    }
}

Describe 'Live region public command contracts' {
    BeforeAll {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module LiveRegion, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LiveRegionModulePath -Force
    }

    AfterAll {
        Remove-Module LiveRegion, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'exports only the nine supported commands as advanced functions with authored help' {
        $commands = @(Get-Command -Module LiveRegion)

        $commands.Name | Sort-Object | Should -Be @(
            'Add-PoshUILiveRegionMessage'
            'Close-PoshUILiveRegion'
            'Format-PoshUILiveRegion'
            'Invoke-PoshUILiveRegion'
            'New-PoshUILiveRegion'
            'Remove-PoshUILiveRegionContent'
            'Set-PoshUILiveRegionContent'
            'Show-PoshUILiveRegion'
            'Update-PoshUILiveRegion'
        )
        foreach ($command in $commands) {
            $command.CmdletBinding | Should -BeTrue -Because $command.Name
            $command.OutputType.Count | Should -BeGreaterThan 0 -Because $command.Name
            (Get-Help $command.Name).Examples.Example.Count | Should -BeGreaterOrEqual 3 -Because $command.Name
        }
    }
}
