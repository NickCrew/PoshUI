#Requires -Version 7.6
# PoshUI.Installer.Tests.ps1 - Pester v5 suite for Install-PoshUIModule.ps1
#
# Dot-sourcing the installer with -WhatIf brings its functions into scope
# without performing an install.

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:InstallerPath = Join-Path $script:ModuleRoot 'tools' 'Install-PoshUIModule.ps1'
    . $script:InstallerPath -DestinationRoot (Join-Path $TestDrive 'bootstrap') -WhatIf

    function script:Get-InstalledCommandCount {
        param(
            [Parameter(Mandatory)]
            [string]$ManifestPath
        )

        # A clean child process, so this suite's own POSH_UI_* state and
        # loaded modules cannot make a broken install look importable. The
        # manifest travels by environment variable: -Command takes no -args.
        $probe = @'
$ErrorActionPreference = "Stop"
$manifest = $env:POSH_UI_PROBE_MANIFEST
Get-ChildItem Env: |
    Where-Object { $_.Name -like "POSH_UI_*" } |
    ForEach-Object { Remove-Item -LiteralPath ("Env:{0}" -f $_.Name) }
Import-Module -Name $manifest -Force
@(Get-Command -Module PoshUI).Count
'@
        try {
            $env:POSH_UI_PROBE_MANIFEST = $ManifestPath
            [int](& pwsh -NoLogo -NoProfile -NonInteractive -Command $probe)
        }
        finally {
            Remove-Item Env:POSH_UI_PROBE_MANIFEST -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Installer path containment' {
    It 'accepts the root itself and true descendants' {
        $root = Join-Path $TestDrive 'home'
        $child = Join-Path $root 'Documents/PowerShell/Modules'
        [void](New-Item -ItemType Directory -Path $child -Force)

        Test-PoshUIPathContained -Candidate $root -Root $root | Should -BeTrue
        Test-PoshUIPathContained -Candidate $child -Root $root | Should -BeTrue
    }

    It 'rejects a sibling that only shares the root path prefix' {
        $root = Join-Path $TestDrive 'user'
        $sibling = Join-Path $TestDrive 'user-other/Modules'
        [void](New-Item -ItemType Directory -Path $root -Force)
        [void](New-Item -ItemType Directory -Path $sibling -Force)

        Test-PoshUIPathContained -Candidate $sibling -Root $root | Should -BeFalse
    }

    It 'normalizes parent segments before checking containment' {
        $root = Join-Path $TestDrive 'normalized'
        $viaParent = Join-Path $root 'Documents/../PowerShell/Modules'
        [void](New-Item -ItemType Directory -Path (Join-Path $root 'PowerShell/Modules') -Force)

        Test-PoshUIPathContained -Candidate $viaParent -Root $root | Should -BeTrue
    }

    It 'rejects a symlink that escapes the root' -Skip:$IsWindows {
        $root = Join-Path $TestDrive 'link-home'
        $outside = Join-Path $TestDrive 'link-outside'
        [void](New-Item -ItemType Directory -Path $root -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $outside 'Modules') -Force)
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $root 'linked') -Target $outside)

        Test-PoshUIPathContained -Candidate (Join-Path $root 'linked/Modules') -Root $root |
            Should -BeFalse
    }
}

Describe 'Module root discoverability' {
    It 'reports a PSModulePath entry as discoverable' {
        $root = Join-Path $TestDrive 'on-path'
        [void](New-Item -ItemType Directory -Path $root -Force)
        $previous = $env:PSModulePath
        try {
            $env:PSModulePath = $root + [IO.Path]::PathSeparator + $previous
            Test-PoshUIModuleRootDiscoverable -ModuleRoot $root | Should -BeTrue
        }
        finally {
            $env:PSModulePath = $previous
        }
    }

    It 'reports a directory that is merely inside a PSModulePath entry as not discoverable' {
        # PSModulePath is searched one level deep. A nested root would install
        # a module PowerShell never finds by name.
        $root = Join-Path $TestDrive 'nested-parent'
        $nested = Join-Path $root 'deeper'
        [void](New-Item -ItemType Directory -Path $nested -Force)
        $previous = $env:PSModulePath
        try {
            $env:PSModulePath = $root + [IO.Path]::PathSeparator + $previous
            Test-PoshUIModuleRootDiscoverable -ModuleRoot $nested | Should -BeFalse
        }
        finally {
            $env:PSModulePath = $previous
        }
    }
}

Describe 'Payload staging' {
    It 'stages every payload entry' {
        $staged = Join-Path $TestDrive 'staged'
        Copy-PoshUIPayload -SourceModule $script:ModuleRoot -StagingModule $staged

        foreach ($entry in @(
                'PoshUI.psd1', 'PoshUI.psm1', 'README.md', 'modules'
            )) {
            Test-Path -LiteralPath (Join-Path $staged $entry) | Should -BeTrue -Because "$entry is part of the payload"
        }
    }

    It 'stages all module files including the runtime policy' {
        $staged = Join-Path $TestDrive 'staged-modules'
        Copy-PoshUIPayload -SourceModule $script:ModuleRoot -StagingModule $staged

        $expected = @(Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot 'modules') -Filter '*.psm1' -File).Count
        @(Get-ChildItem -LiteralPath (Join-Path $staged 'modules') -Filter '*.psm1' -File).Count |
            Should -Be $expected
    }

    It 'does not stage untracked local output sitting in the source root' {
        # The payload is an allow-list precisely so gitignored artifacts such
        # as benchmark_results.txt never ship.
        $source = Join-Path $TestDrive 'dirty-source'
        [void](New-Item -ItemType Directory -Path (Join-Path $source 'modules') -Force)
        foreach ($entry in @('PoshUI.psd1', 'PoshUI.psm1', 'README.md')) {
            'x' | Set-Content -LiteralPath (Join-Path $source $entry)
        }
        [void](New-Item -ItemType Directory -Path (Join-Path $source 'repo-only') -Force)
        'noise' | Set-Content -LiteralPath (Join-Path $source 'benchmark_results.txt')

        $staged = Join-Path $TestDrive 'staged-clean'
        Copy-PoshUIPayload -SourceModule $source -StagingModule $staged

        Test-Path -LiteralPath (Join-Path $staged 'benchmark_results.txt') | Should -BeFalse
    }

    It 'throws when a payload entry is missing' {
        $source = Join-Path $TestDrive 'incomplete-source'
        [void](New-Item -ItemType Directory -Path $source -Force)
        'x' | Set-Content -LiteralPath (Join-Path $source 'PoshUI.psd1')

        { Copy-PoshUIPayload -SourceModule $source -StagingModule (Join-Path $TestDrive 'staged-incomplete') } |
            Should -Throw -ExpectedMessage '*is missing from*'
    }
}

Describe 'Install' {
    BeforeAll {
        $script:InstallRoot = Join-Path $TestDrive 'install-root'
        $script:Installed = Invoke-PoshUIModuleInstall `
            -SourceModule $script:ModuleRoot `
            -ModuleRoot $script:InstallRoot
    }

    It 'installs into a folder named for the module' {
        $version = (Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'PoshUI.psd1')).ModuleVersion
        $script:Installed | Should -Be (Join-Path (Join-Path $script:InstallRoot 'PoshUI') $version)
        Test-Path -LiteralPath (Join-Path $script:Installed 'PoshUI.psd1') | Should -BeTrue
    }

    It 'leaves no staging or backup directory behind' {
        @(Get-ChildItem -LiteralPath $script:InstallRoot -Directory -Recurse -Force |
                Where-Object { $_.Name -like '.PoshUI.*' }).Count | Should -Be 0
    }

    It 'produces an installed module that imports and exports commands' {
        Get-InstalledCommandCount -ManifestPath (Join-Path $script:Installed 'PoshUI.psd1') |
            Should -BeGreaterThan 0
    }

    It 'replaces the previous install rather than merging into it' {
        $stale = Join-Path $script:Installed 'STALE.txt'
        'leftover' | Set-Content -LiteralPath $stale

        [void](Invoke-PoshUIModuleInstall -SourceModule $script:ModuleRoot -ModuleRoot $script:InstallRoot)

        Test-Path -LiteralPath $stale | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Installed 'PoshUI.psd1') | Should -BeTrue
    }

    # Synthetic paths, not the real tree: the guards are about path
    # relationships, and a checkout and an installed copy nest differently.
    It 'refuses a destination inside the source module' {
        $source = Join-Path $TestDrive 'overlap-source'
        { Invoke-PoshUIModuleInstall `
                -SourceModule $source `
                -ModuleRoot (Join-Path $source 'nested') } |
            Should -Throw -ExpectedMessage '*inside the source module*'
    }

    It 'refuses a destination that contains the source module' {
        $root = Join-Path $TestDrive 'contain-root'
        { Invoke-PoshUIModuleInstall `
                -SourceModule (Join-Path $root 'PoshUI' 'nested') `
                -ModuleRoot $root } |
            Should -Throw -ExpectedMessage '*is inside it*'
    }

    It 'creates nothing when the destination is refused' {
        $root = Join-Path $TestDrive 'refused-root'
        { Invoke-PoshUIModuleInstall `
                -SourceModule (Join-Path $root 'PoshUI' 'nested') `
                -ModuleRoot $root } | Should -Throw

        Test-Path -LiteralPath $root | Should -BeFalse
    }
}

Describe 'Failed install' {
    It 'keeps the previous install in place when validation fails' {
        $root = Join-Path $TestDrive 'rollback-root'
        $destination = Invoke-PoshUIModuleInstall -SourceModule $script:ModuleRoot -ModuleRoot $root
        'previous' | Set-Content -LiteralPath (Join-Path $destination 'MARKER.txt')

        # A source whose manifest cannot import: staging succeeds, the
        # clean-process validation does not.
        $broken = Join-Path $TestDrive 'broken-source'
        [void](New-Item -ItemType Directory -Path $broken -Force)
        Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'modules') -Destination (Join-Path $broken 'modules') -Recurse
        'x' | Set-Content -LiteralPath (Join-Path $broken 'README.md')
        'throw "broken module"' | Set-Content -LiteralPath (Join-Path $broken 'PoshUI.psm1')
        @'
@{
    RootModule        = 'PoshUI.psm1'
    ModuleVersion     = '9.9.9'
    GUID              = '84b14dbb-6ec2-4338-b0a2-bff6199424f1'
    Description       = 'broken fixture'
    PowerShellVersion = '7.0'
    FunctionsToExport = '*'
}
'@ | Set-Content -LiteralPath (Join-Path $broken 'PoshUI.psd1')

        { Invoke-PoshUIModuleInstall -SourceModule $broken -ModuleRoot $root } |
            Should -Throw -ExpectedMessage '*failed clean-process import validation*'

        Test-Path -LiteralPath (Join-Path $destination 'MARKER.txt') | Should -BeTrue
        (Test-ModuleManifest -Path (Join-Path $destination 'PoshUI.psd1')).Version.ToString() |
            Should -Not -Be '9.9.9'
        @(Get-ChildItem -LiteralPath $root -Directory -Force |
                Where-Object { $_.Name -like '.PoshUI.stage.*' }).Count | Should -Be 0
    }
}

Describe 'Installer actions' {
    BeforeAll {
        $script:ActionRoot = Join-Path $TestDrive 'action-root'
    }

    It 'reports Not installed before an install' {
        $output = & $script:InstallerPath -Action Status -DestinationRoot $script:ActionRoot
        ($output -join "`n") | Should -Match 'Status:\s+Not installed'
    }

    It 'installs, then reports the manifest version' {
        & $script:InstallerPath -DestinationRoot $script:ActionRoot -InformationAction SilentlyContinue
        $expected = (Test-ModuleManifest -Path (Join-Path $script:ModuleRoot 'PoshUI.psd1')).Version.ToString()

        $output = (& $script:InstallerPath -Action Status -DestinationRoot $script:ActionRoot) -join "`n"
        $output | Should -Match 'Status:\s+Installed'
        $output | Should -Match ([regex]::Escape($expected))
    }

    It 'uninstalls the module folder' {
        & $script:InstallerPath -Action Uninstall -DestinationRoot $script:ActionRoot -InformationAction SilentlyContinue

        Test-Path -LiteralPath (Join-Path $script:ActionRoot 'PoshUI') | Should -BeFalse
        ((& $script:InstallerPath -Action Status -DestinationRoot $script:ActionRoot) -join "`n") |
            Should -Match 'Status:\s+Not installed'
    }

    It 'changes nothing under -WhatIf' {
        $root = Join-Path $TestDrive 'whatif-root'
        & $script:InstallerPath -DestinationRoot $root -WhatIf

        Test-Path -LiteralPath (Join-Path $root 'PoshUI') | Should -BeFalse
    }

    It 'rejects an unknown action' {
        { & $script:InstallerPath -Action Reinstall -DestinationRoot $script:ActionRoot } | Should -Throw
    }
}

Describe 'Installed runtime layout' {
    BeforeAll {
        $script:LayoutRoot = Join-Path $TestDrive 'layout-root'
        $script:LayoutModule = Invoke-PoshUIModuleInstall `
            -SourceModule $script:ModuleRoot `
            -ModuleRoot $script:LayoutRoot
    }

    It 'uses the standard versioned module directory' {
        Split-Path -Leaf $script:LayoutModule | Should -Be $script:ModuleVersion
        Test-Path (Join-Path $script:LayoutModule 'PoshUI.psd1') | Should -BeTrue
    }

    It 'excludes repository development assets' {
        foreach ($entry in @('bin', 'examples', 'tests', 'tools')) {
            Test-Path (Join-Path $script:LayoutModule $entry) | Should -BeFalse
        }
    }
}
