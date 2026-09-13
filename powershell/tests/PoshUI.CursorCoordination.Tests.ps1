#Requires -Version 7.6

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules')).Path
    $script:LiveRegionPath = Join-Path $script:ModuleRoot 'LiveRegion.psm1'
    $script:SearchPath = Join-Path $script:ModuleRoot 'SearchableSelection.psm1'
}

Describe 'Cross-module cursor coordination' {
    BeforeEach {
        $env:POSH_UI_MODE = 'rich'
        Get-Module -All LiveRegion, SearchableSelection, Layout, Runtime |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    AfterEach {
        Get-Module -All LiveRegion, SearchableSelection, Layout, Runtime |
            Remove-Module -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'releases cursor ownership when a live region closes' {
        Import-Module $script:LiveRegionPath -Force
        Mock Test-PoshUITerminalControl { $true } -ModuleName LiveRegion
        Mock Write-PoshUILiveRichSnapshotInternal {} -ModuleName LiveRegion
        Mock Write-PoshUILiveCursorVisibilityInternal {} -ModuleName LiveRegion
        $first = New-PoshUILiveRegion -Name first
        $second = New-PoshUILiveRegion -Name second
        Set-PoshUILiveRegionContent $first job Running
        Set-PoshUILiveRegionContent $second job Waiting
        Show-PoshUILiveRegion $first
        { Show-PoshUILiveRegion $second } | Should -Throw '*owns the terminal cursor*'
        Close-PoshUILiveRegion $first
        $third = New-PoshUILiveRegion -Name third
        Set-PoshUILiveRegionContent $third job Ready
        { Show-PoshUILiveRegion $third } | Should -Not -Throw
        Close-PoshUILiveRegion $third
    }

    It 'sanitizes control input before live rendering' {
        Import-Module $script:LiveRegionPath -Force
        $region = New-PoshUILiveRegion -Name safe
        Set-PoshUILiveRegionContent $region item "safe`e]52;c;secret`a`e[2Jvisible"
        $rendered = Format-PoshUILiveRegion $region
        $rendered -join '' | Should -Not -Match ([regex]::Escape("`e]52"))
        $rendered -join '' | Should -Not -Match ([regex]::Escape("`e[2J"))
    }
}
