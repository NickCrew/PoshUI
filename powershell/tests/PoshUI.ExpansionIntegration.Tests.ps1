#Requires -Version 7.6

BeforeAll {
    $script:ManifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PoshUI.psd1')).Path
    $script:DemoPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'examples' 'Demo.ps1')).Path

    function script:Invoke-ExpansionProbe {
        param(
            [Parameter(Mandatory)][string]$Body,
            [hashtable]$Environment = @{}
        )

        $previous = @{}
        try {
            $Environment['POSHUI_EXPANSION_MANIFEST'] = $script:ManifestPath
            foreach ($entry in $Environment.GetEnumerator()) {
                $previous[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
                [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value)
            }
            $output = @($null | & pwsh -NoLogo -NoProfile -NonInteractive -Command $Body 2>&1)
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        finally {
            foreach ($entry in $previous.GetEnumerator()) {
                [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
            }
        }
    }
}

Describe 'Expansion root integration' {
    It 'exports the complete explicit expansion inventory' {
        $probe = Invoke-ExpansionProbe -Body @'
$env:POSH_UI_MODE = 'off'
$module = Import-Module $env:POSHUI_EXPANSION_MANIFEST -Force -PassThru -ErrorAction Stop
[pscustomobject]@{
    Count = $module.ExportedCommands.Count
    Layout = $module.ExportedCommands.ContainsKey('Format-PoshUIGrid')
    Data = $module.ExportedCommands.ContainsKey('Format-PoshUIDataTable')
    Live = $module.ExportedCommands.ContainsKey('New-PoshUILiveRegion')
    Tree = $module.ExportedCommands.ContainsKey('Format-PoshUITree')
    Search = $module.ExportedCommands.ContainsKey('Select-PoshUIItem')
    Diff = $module.ExportedCommands.ContainsKey('Format-PoshUIDiff')
    Stepper = $module.ExportedCommands.ContainsKey('New-PoshUIStepper')
} | ConvertTo-Json -Compress
'@

        $probe.ExitCode | Should -Be 0
        $result = ($probe.Output -join "`n") | ConvertFrom-Json
        $result.Count | Should -Be 82
        $result.Layout | Should -BeTrue
        $result.Data | Should -BeTrue
        $result.Live | Should -BeTrue
        $result.Tree | Should -BeTrue
        $result.Search | Should -BeTrue
        $result.Diff | Should -BeTrue
        $result.Stepper | Should -BeTrue
    }

    It 'filters disabled expansion modules through the explicit inventory' {
        $probe = Invoke-ExpansionProbe -Environment @{ POSH_UI_LOAD_DATATABLE = 'false' } -Body @'
$env:POSH_UI_MODE = 'off'
$module = Import-Module $env:POSHUI_EXPANSION_MANIFEST -Force -PassThru -ErrorAction Stop
[pscustomobject]@{
    Data = $module.ExportedCommands.ContainsKey('Format-PoshUIDataTable')
    Layout = $module.ExportedCommands.ContainsKey('Format-PoshUIGrid')
    Config = $module.ExportedCommands.ContainsKey('Get-PoshUIConfiguration')
} | ConvertTo-Json -Compress
'@

        $probe.ExitCode | Should -Be 0
        $result = ($probe.Output -join "`n") | ConvertFrom-Json
        $result.Data | Should -BeFalse
        $result.Layout | Should -BeTrue
        $result.Config | Should -BeTrue
    }

    It 'keeps expansion modules out of minimal mode' {
        $probe = Invoke-ExpansionProbe -Body @'
$env:POSH_UI_MODE = 'off'
$module = Import-Module $env:POSHUI_EXPANSION_MANIFEST -ArgumentList '--minimal' -Force -PassThru -ErrorAction Stop
[pscustomobject]@{
    Expansion = $module.ExportedCommands.ContainsKey('Format-PoshUIPanel')
    Header = $module.ExportedCommands.ContainsKey('Format-PoshUIHeader')
    Config = $module.ExportedCommands.ContainsKey('Get-PoshUIConfiguration')
} | ConvertTo-Json -Compress
'@

        $probe.ExitCode | Should -Be 0
        $result = ($probe.Output -join "`n") | ConvertFrom-Json
        $result.Expansion | Should -BeFalse
        $result.Header | Should -BeTrue
        $result.Config | Should -BeTrue
    }

    It 'composes object data into layout without host effects' {
        $env:POSH_UI_MODE = 'plain'
        try {
            Import-Module $script:ManifestPath -Force
            $rows = @(
                [pscustomobject]@{ Service = 'api'; Status = 'healthy' }
                [pscustomobject]@{ Service = 'worker'; Status = 'queued' }
            ) | Format-PoshUIDataTable -Property Service, Status

            $information = @()
            $panel = @($rows | Format-PoshUIPanel -Title Services -Width 32 -InformationVariable information)

            $panel[0] | Should -Be '╭ Services ────────────────────╮'
            $panel | Should -Contain '│ | api     | healthy |        │'
            $panel[-1] | Should -Be '╰──────────────────────────────╯'
            $information | Should -BeNullOrEmpty
        }
        finally {
            Remove-Module PoshUI -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
        }
    }

    It 'runs the migrated release-console example to completion' {
        $probe = Invoke-ExpansionProbe -Environment @{
            POSH_UI_MODE = 'off'
            POSHUI_DEMO_PATH = $script:DemoPath
        } -Body @'
function global:Clear-Host { throw 'The redirected demo must not clear the host.' }
& $env:POSHUI_DEMO_PATH
'@

        $probe.ExitCode | Should -Be 0 -Because ($probe.Output -join [Environment]::NewLine)
    }
}
