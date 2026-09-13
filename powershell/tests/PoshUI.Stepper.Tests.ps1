#Requires -Version 7.6

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'Stepper.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'PoshUI stepper state' {
    It 'keeps independently updated instances isolated' {
        $first = New-PoshUIStepper -Title First
        $second = New-PoshUIStepper -Title Second
        $first = Add-PoshUIStep $first build Build
        $second = Add-PoshUIStep $second deploy Deploy -State Active
        $first = Set-PoshUIStep -Stepper $first -Id build -State Success

        $first.Steps[0].State | Should -Be 'Success'
        $second.Steps[0].State | Should -Be 'Active'
        [object]::ReferenceEquals($first.Steps, $second.Steps) | Should -BeFalse
    }

    It 'retains typed values and timestamps' {
        $value = [pscustomobject]@{ Version = '1.2.3' }
        $timestamp = [datetime]'2026-08-26T12:00:00Z'
        $steps = New-PoshUIStepper
        $steps = Add-PoshUIStep -Stepper $steps -Id deploy -Label Deploy -Value $value -Timestamp $timestamp
        [object]::ReferenceEquals($steps.Steps[0].Value, $value) | Should -BeTrue
        $steps.Steps[0].Timestamp | Should -Be $timestamp
    }

    It 'rejects duplicate and unknown identifiers' {
        $steps = Add-PoshUIStep (New-PoshUIStepper) build Build
        { Add-PoshUIStep $steps build Again } | Should -Throw '*already exists*'
        { Set-PoshUIStep $steps missing -State Failed } | Should -Throw '*No step*exists*'
    }
}

Describe 'PoshUI stepper rendering' {
    BeforeEach {
        $script:Steps = New-PoshUIStepper -Title Deploy
        $script:Steps = Add-PoshUIStep $script:Steps plan Plan -State Pending
        $script:Steps = Add-PoshUIStep $script:Steps run Run -State Active -Description Working
        $script:Steps = Add-PoshUIStep $script:Steps verify Verify -State Success
        $script:Steps = Add-PoshUIStep $script:Steps notify Notify -State Failed
        $script:Steps = Add-PoshUIStep $script:Steps cleanup Cleanup -State Skipped
    }

    It 'renders all states as text in compact ASCII form' {
        @(Format-PoshUIStepper $script:Steps -CharacterSet ASCII) | Should -Be @(
            'Deploy'
            'o [PENDING] Plan'
            '|'
            '> [ACTIVE] Run'
            '|'
            '+ [SUCCESS] Verify'
            '|'
            'x [FAILED] Notify'
            '|'
            '- [SKIPPED] Cleanup'
        )
    }

    It 'renders detail and timestamps without mutating the model' {
        $script:Steps = Set-PoshUIStep $script:Steps run -Timestamp ([datetime]'2026-08-26T12:34:00')
        $before = $script:Steps | ConvertTo-Json -Depth 5 -Compress
        $actual = @(Format-PoshUIStepper $script:Steps -Style Expanded -TimestampFormat 'HH:mm')
        $actual | Should -Contain '◉ [ACTIVE] 12:34 Run'
        $actual | Should -Contain '  │ Working'
        ($script:Steps | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly $before
    }

    It 'uses layout wrapping for narrow Unicode labels' {
        $steps = New-PoshUIStepper
        $steps = Add-PoshUIStep $steps deploy '部署👨‍👩‍👧‍👦' -State Active
        @(Format-PoshUIStepper $steps -Width 12 -Overflow Wrap) | Should -Be @(
            '◉ [ACTIVE]'
            '部署👨‍👩‍👧‍👦'
        )
    }

    It 'uses layout truncation without splitting Unicode graphemes' {
        $steps = New-PoshUIStepper
        $steps = Add-PoshUIStep $steps deploy '部署👨‍👩‍👧‍👦' -State Pending
        Format-PoshUIStepper $steps -Width 12 -Overflow Truncate | Should -BeExactly '○ [PENDING]…'
    }

    It 'routes display through the runtime boundary' {
        InModuleScope Stepper -Parameters @{ Model = $script:Steps } {
            Mock Write-PoshUIHost
            Show-PoshUIStepper -Stepper $Model -CharacterSet ASCII
            Should -Invoke Write-PoshUIHost -Exactly 10
        }
    }

    It 'uses the real plain and off host boundaries' {
        $steps = Add-PoshUIStep (New-PoshUIStepper) build Build
        $previous = $env:POSH_UI_MODE
        try {
            $env:POSH_UI_MODE = 'plain'
            @(& { Show-PoshUIStepper $steps } 6>&1 | ForEach-Object { [string]$_ }) | Should -Be @('○ [PENDING] Build')

            $env:POSH_UI_MODE = 'off'
            @(& { Show-PoshUIStepper $steps } 6>&1) | Should -BeNullOrEmpty
        }
        finally { $env:POSH_UI_MODE = $previous }
    }
}

Describe 'PoshUI stepper command contracts' {
    It 'publishes advanced commands with authored help and output metadata' -ForEach @(
        'New-PoshUIStepper', 'Add-PoshUIStep', 'Set-PoshUIStep', 'Format-PoshUIStepper', 'Show-PoshUIStepper'
    ) {
        $command = Get-Command $_ -Module Stepper
        $command.CmdletBinding | Should -BeTrue
        $command.OutputType.Count | Should -BeGreaterThan 0
        (Get-Help $_).Synopsis | Should -Not -BeNullOrEmpty
        @((Get-Help $_).Examples.Example).Count | Should -BeGreaterOrEqual 3
    }
}
