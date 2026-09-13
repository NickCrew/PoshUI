#Requires -Version 7.6

$script:ArchitectureCommands = @(
    'Get-PoshUIConfiguration'
    'Get-PoshUIRuntime'
    'New-PoshUITheme'
    'Set-PoshUITheme'
    'Set-PoshUILogConfiguration'
    'Get-PoshUILogConfiguration'
    'Write-PoshUILog'
    'Clear-PoshUILog'
    'Format-PoshUIHeader'
    'Show-PoshUIHeader'
    'Format-PoshUISubheader'
    'Show-PoshUISubheader'
    'Format-PoshUIStatus'
    'New-PoshUIProgress'
    'Update-PoshUIProgress'
    'Format-PoshUIProgress'
    'Show-PoshUIProgress'
    'Format-PoshUIBox'
    'Show-PoshUIBox'
    'New-PoshUITable'
    'Set-PoshUITableHeader'
    'Add-PoshUITableRow'
    'Set-PoshUITableAlignment'
    'Format-PoshUITable'
    'Show-PoshUITable'
    'Format-PoshUIHorizontalBarChart'
    'Show-PoshUIHorizontalBarChart'
    'Format-PoshUISparkline'
    'Show-PoshUISparkline'
    'Format-PoshUIGauge'
    'Show-PoshUIGauge'
    'New-PoshUIMenu'
    'Add-PoshUIMenuItem'
    'Format-PoshUIMenu'
    'Show-PoshUIMenu'
    'Invoke-PoshUIMenuAction'
    'Read-PoshUIText'
    'Read-PoshUIPassword'
    'Confirm-PoshUIChoice'
    'Select-PoshUIOption'
    'Select-PoshUIMultipleOption'
    'Read-PoshUINumber'
    'Read-PoshUIFilePath'
    'Read-PoshUIDirectoryPath'
    'Format-PoshUIText'
    'Format-PoshUIPanel'
    'Show-PoshUIPanel'
    'Format-PoshUIStack'
    'Show-PoshUIStack'
    'Format-PoshUIColumn'
    'Show-PoshUIColumn'
    'Format-PoshUIGrid'
    'Show-PoshUIGrid'
    'New-PoshUIDataColumn'
    'Format-PoshUIDataTable'
    'Show-PoshUIDataTable'
    'Format-PoshUITree'
    'Show-PoshUITree'
    'Format-PoshUICodeBlock'
    'Show-PoshUICodeBlock'
    'Format-PoshUIDiff'
    'Show-PoshUIDiff'
    'New-PoshUIStepper'
    'Add-PoshUIStep'
    'Set-PoshUIStep'
    'Format-PoshUIStepper'
    'Show-PoshUIStepper'
    'New-PoshUILiveRegion'
    'Set-PoshUILiveRegionContent'
    'Remove-PoshUILiveRegionContent'
    'Add-PoshUILiveRegionMessage'
    'Format-PoshUILiveRegion'
    'Show-PoshUILiveRegion'
    'Update-PoshUILiveRegion'
    'Close-PoshUILiveRegion'
    'Invoke-PoshUILiveRegion'
    'New-PoshUISelectionItem'
    'Find-PoshUISelectionItem'
    'New-PoshUISearchSelection'
    'Update-PoshUISearchSelection'
    'Format-PoshUISearchSelection'
    'Select-PoshUIItem'
)

$script:ArchitectureCommandCases = foreach ($name in $script:ArchitectureCommands) {
    @{ Name = $name }
}

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
    $env:POSH_UI_MODE = 'off'
    Import-Module $script:ManifestPath -Force
    $script:PublicNames = @((Import-PowerShellDataFile -LiteralPath $script:ManifestPath).FunctionsToExport)
}

AfterAll {
    Remove-Module PoshUI -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
}

Describe 'Public command contracts' {
    It 'publishes every supported command as an advanced function' {
        $notAdvanced = @(
            foreach ($name in $script:PublicNames) {
                $command = Get-Command -Name $name -Module PoshUI
                if (-not $command.CmdletBinding) { $name }
            }
        )

        $notAdvanced | Should -BeNullOrEmpty
    }

    It 'keeps private helpers out of the supported inventory' {
        @($script:PublicNames | Where-Object { $_ -like '_*' }) | Should -BeNullOrEmpty
    }

    It 'provides complete authored help for <Name>' -ForEach $script:ArchitectureCommandCases {
        $help = Get-Help -Name $Name -Full

        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Be $Name
        [string]$help.Description.Text | Should -Not -BeNullOrEmpty
        @($help.Examples.Example) | Should -HaveCount 3
    }

    It 'declares output metadata for <Name>' -ForEach $script:ArchitectureCommandCases {
        $command = Get-Command -Name $Name -Module PoshUI
        @($command.OutputType) | Should -Not -BeNullOrEmpty
    }
}
