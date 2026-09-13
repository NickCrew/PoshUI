#Requires -Version 7.6

BeforeAll {
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'modules')).Path
    $script:LoggingPath = Join-Path $script:ModuleRoot 'Logging.psm1'
}

Describe 'Native JSONL logging' {
    BeforeEach {
        $env:POSH_UI_MODE = 'plain'
        Remove-Module Logging, Colors, Configuration, Runtime -Force -ErrorAction SilentlyContinue
        Import-Module $script:LoggingPath -Force
        Set-PoshUILogConfiguration -Level Info -FilePath '' -ConsoleOutput $false `
            -MaximumSize 10MB -MaximumFiles 5
    }

    AfterEach {
        Remove-Module Logging, Colors, Configuration, Runtime -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\POSH_UI_MODE -ErrorAction SilentlyContinue
    }

    It 'writes one parseable UTF-8 JSON object per event' {
        $path = Join-Path $TestDrive 'nested' 'events.jsonl'
        Set-PoshUILogConfiguration -FilePath $path

        Write-PoshUILog -Level Info -Message "Deployed `"CRM`"`nready" -Data ([ordered]@{
                environment = 'stage'
                version = '26.8.3'
                count = 2
                healthy = $true
                note = $null
                unicode = 'café ✓'
            })

        $lines = @([IO.File]::ReadAllLines($path))
        $lines | Should -HaveCount 1
        $logEvent = $lines[0] | ConvertFrom-Json
        $logEvent.schemaVersion | Should -Be 1
        [DateTimeOffset]::Parse($logEvent.timestamp) | Should -Not -BeNullOrEmpty
        $logEvent.level | Should -BeExactly 'INFO'
        $logEvent.message | Should -Be "Deployed `"CRM`"`nready"
        $logEvent.data.environment | Should -BeExactly 'stage'
        $logEvent.data.count | Should -Be 2
        $logEvent.data.healthy | Should -BeTrue
        $logEvent.data.note | Should -BeNullOrEmpty
        $logEvent.data.unicode | Should -BeExactly 'café ✓'
        [IO.File]::ReadAllBytes($path)[0..2] | Should -Not -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'sanitizes terminal controls without corrupting the JSONL boundary' {
        $path = Join-Path $TestDrive 'safe.jsonl'
        Set-PoshUILogConfiguration -FilePath $path
        $hostile = "before`e]52;c;secret`a`e[2J`e[31mvisible`e[0m$([char]8)after"

        Write-PoshUILog -Level Warning -Message $hostile

        $lines = @([IO.File]::ReadAllLines($path))
        $lines | Should -HaveCount 1
        $logEvent = $lines[0] | ConvertFrom-Json
        $logEvent.message | Should -BeExactly 'beforevisibleafter'
    }

    It 'filters before file effects and preserves accepted event order' {
        $path = Join-Path $TestDrive 'filtered.jsonl'
        Set-PoshUILogConfiguration -Level Warning -FilePath $path

        Write-PoshUILog -Level Debug -Message 'hidden'
        Write-PoshUILog -Level Error -Message 'first'
        Write-PoshUILog -Level Fatal -Message 'second'

        $events = @([IO.File]::ReadAllLines($path) | ForEach-Object { $_ | ConvertFrom-Json })
        $events | Should -HaveCount 2
        @($events.message) | Should -Be @('first', 'second')
        @($events.level) | Should -Be @('ERROR', 'FATAL')
    }

    It 'treats fatal as a level without terminating the caller' {
        $path = Join-Path $TestDrive 'fatal.jsonl'
        Set-PoshUILogConfiguration -FilePath $path

        Write-PoshUILog -Level Fatal -Message 'stop requested'
        $continued = $true

        $continued | Should -BeTrue
        ([IO.File]::ReadAllText($path) | ConvertFrom-Json).level | Should -BeExactly 'FATAL'
    }

    It 'reports an actionable file-write failure' {
        $directory = Join-Path $TestDrive 'not-a-file'
        New-Item -ItemType Directory -Path $directory | Out-Null
        Set-PoshUILogConfiguration -FilePath $directory

        { Write-PoshUILog -Level Error -Message 'cannot append' } |
            Should -Throw "*Failed to append PoshUI log file '$directory'*"
    }

    It 'suppresses console and file effects in off mode' {
        $path = Join-Path $TestDrive 'off.jsonl'
        Set-PoshUILogConfiguration -FilePath $path -ConsoleOutput $true
        $env:POSH_UI_MODE = 'off'

        $output = @(& { Write-PoshUILog -Level Error -Message 'hidden' } *>&1)

        $output | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'does not create sink directories when configured in off mode' {
        $path = Join-Path $TestDrive 'off-nested' 'events.jsonl'
        $env:POSH_UI_MODE = 'off'

        Set-PoshUILogConfiguration -FilePath $path

        Test-Path -LiteralPath (Split-Path -Parent $path) | Should -BeFalse
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'creates a missing sink directory on the first accepted event' {
        $path = Join-Path $TestDrive 'startup-nested' 'events.jsonl'
        Set-PoshUILogConfiguration -FilePath $path
        Write-PoshUILog -Level Info -Message 'startup event'

        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).message |
            Should -BeExactly 'startup event'
    }

    It 'rotates before an accepted event would exceed the byte limit' {
        $path = Join-Path $TestDrive 'rotate.jsonl'
        Set-PoshUILogConfiguration -FilePath $path -MaximumSize 1 -MaximumFiles 2

        Write-PoshUILog -Level Info -Message 'one'
        Write-PoshUILog -Level Info -Message 'two'
        Write-PoshUILog -Level Info -Message 'three'
        Write-PoshUILog -Level Info -Message 'four'

        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).message | Should -BeExactly 'four'
        (Get-Content -LiteralPath "$path.1" -Raw | ConvertFrom-Json).message | Should -BeExactly 'three'
        (Get-Content -LiteralPath "$path.2" -Raw | ConvertFrom-Json).message | Should -BeExactly 'two'
        Test-Path -LiteralPath "$path.3" | Should -BeFalse
    }

    It 'enforces a reduced archive limit on the next rotation' {
        $path = Join-Path $TestDrive 'reduced-retention.jsonl'
        Set-PoshUILogConfiguration -FilePath $path -MaximumSize 1 -MaximumFiles 5
        1..6 | ForEach-Object { Write-PoshUILog -Level Info -Message "event $_" }

        Set-PoshUILogConfiguration -MaximumFiles 2
        Write-PoshUILog -Level Info -Message 'after reduction'

        Test-Path -LiteralPath "$path.1" | Should -BeTrue
        Test-Path -LiteralPath "$path.2" | Should -BeTrue
        Test-Path -LiteralPath "$path.3" | Should -BeFalse
        Test-Path -LiteralPath "$path.4" | Should -BeFalse
        Test-Path -LiteralPath "$path.5" | Should -BeFalse
    }

    It 'clears the active sink and is harmless when no sink exists' {
        $path = Join-Path $TestDrive 'clear.jsonl'
        Set-PoshUILogConfiguration -FilePath $path
        Write-PoshUILog -Level Info -Message 'remove me'

        Clear-PoshUILog -Confirm:$false
        [IO.File]::ReadAllText($path) | Should -BeExactly ''
        Set-PoshUILogConfiguration -FilePath (Join-Path $TestDrive 'missing.jsonl')
        { Clear-PoshUILog -Confirm:$false } | Should -Not -Throw
    }

    It 'honors WhatIf without changing the sink' {
        $path = Join-Path $TestDrive 'whatif.jsonl'
        Set-PoshUILogConfiguration -FilePath $path
        Write-PoshUILog -Level Info -Message keep

        Clear-PoshUILog -WhatIf

        (Get-Content $path -Raw | ConvertFrom-Json).message | Should -BeExactly 'keep'
    }

    It 'keeps concurrent writers on valid JSONL record boundaries' {
        $path = Join-Path $TestDrive 'concurrent.jsonl'
        $loggingPath = $script:LoggingPath

        1..4 | ForEach-Object -Parallel {
            $env:POSH_UI_MODE = 'plain'
            Import-Module $using:loggingPath -Force
            Set-PoshUILogConfiguration -FilePath $using:path -ConsoleOutput $false
            $writer = $_
            1..10 | ForEach-Object {
                Write-PoshUILog -Level Info -Message "writer-$writer-event-$_"
            }
        } -ThrottleLimit 4

        $lines = @([IO.File]::ReadAllLines($path))
        $lines | Should -HaveCount 40
        { $lines | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction Stop } } | Should -Not -Throw
        @($lines | ForEach-Object { ($_ | ConvertFrom-Json).message } | Sort-Object -Unique) |
            Should -HaveCount 40
    }

    It 'serializes rotation and writes across independent pwsh processes' {
        $realDirectory = Join-Path $TestDrive 'real-log-directory'
        New-Item -ItemType Directory -Path $realDirectory | Out-Null
        $path = Join-Path $realDirectory 'process-concurrent.jsonl'
        $aliasDirectory = Join-Path $TestDrive 'log-directory-alias'
        $aliasPath = $null
        try {
            New-Item -ItemType SymbolicLink -Path $aliasDirectory -Target $realDirectory -ErrorAction Stop | Out-Null
            $aliasPath = Join-Path $aliasDirectory 'process-concurrent.jsonl'
        }
        catch {
            Write-Verbose "Symbolic-link alias coverage is unavailable: $($_.Exception.Message)"
        }
        $goPath = Join-Path $TestDrive 'process-concurrent.go'
        $workerPath = Join-Path $TestDrive 'log-worker.ps1'
        $workerScript = @'
param($ModulePath, $LogPath, $GoPath, $ReadyPath, [int]$Writer)
$ErrorActionPreference = 'Stop'
$env:POSH_UI_MODE = 'plain'
Import-Module $ModulePath -Force
Set-PoshUILogConfiguration -FilePath $LogPath -ConsoleOutput $false -MaximumSize 256 -MaximumFiles 100
[IO.File]::WriteAllText($ReadyPath, 'ready')
while (-not (Test-Path -LiteralPath $GoPath -PathType Leaf)) {
    Start-Sleep -Milliseconds 10
}
1..10 | ForEach-Object {
    Write-PoshUILog -Level Info -Message "writer-$Writer-event-$_"
}
'@
        Set-Content -LiteralPath $workerPath -Value $workerScript -Encoding utf8
        $processes = [System.Collections.Generic.List[Diagnostics.Process]]::new()
        try {
            foreach ($writer in 1..4) {
                $readyPath = Join-Path $TestDrive "worker-$writer.ready"
                $writerPath = if ($aliasPath -and $writer % 2 -eq 0) { $aliasPath } else { $path }
                $arguments = @(
                    '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $workerPath,
                    $script:LoggingPath, $writerPath, $goPath, $readyPath, [string]$writer
                )
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = (Get-Process -Id $PID).Path
                $startInfo.UseShellExecute = $false
                foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }
                $process = [Diagnostics.Process]::Start($startInfo)
                $processes.Add($process)
            }

            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            do {
                $readyCount = @(Get-ChildItem -LiteralPath $TestDrive -Filter 'worker-*.ready' -File).Count
                if ($readyCount -eq 4) { break }
                Start-Sleep -Milliseconds 25
            } while ([DateTime]::UtcNow -lt $deadline)
            $readyCount | Should -Be 4
            Set-Content -LiteralPath $goPath -Value 'go' -NoNewline

            foreach ($process in $processes) {
                $process.WaitForExit(30000) | Should -BeTrue
                $process.ExitCode | Should -Be 0
            }

            $logFiles = @(Get-ChildItem -LiteralPath $realDirectory -Filter 'process-concurrent.jsonl*' -File)
            $lines = @($logFiles | ForEach-Object { [IO.File]::ReadAllLines($_.FullName) })
            $lines | Should -HaveCount 40
            { $lines | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction Stop } } | Should -Not -Throw
            @($lines | ForEach-Object { ($_ | ConvertFrom-Json).message } | Sort-Object -Unique) |
                Should -HaveCount 40
        }
        finally {
            foreach ($process in $processes) {
                if (-not $process.HasExited) { $process.Kill($true) }
                $process.Dispose()
            }
        }
    }

    It 'returns configuration copies and does not mutate environment inputs' {
        $before = [Environment]::GetEnvironmentVariable('PO_LOG_LEVEL')
        Set-PoshUILogConfiguration -Level Debug -ConsoleOutput $true

        $first = Get-PoshUILogConfiguration
        $first.Level = 'FATAL'
        $second = Get-PoshUILogConfiguration

        $second.Level | Should -BeExactly 'DEBUG'
        $second.ConsoleOutput | Should -BeTrue
        [Environment]::GetEnvironmentVariable('PO_LOG_LEVEL') | Should -BeExactly $before
    }

    It 'rejects invalid configuration before creating a sink' {
        $path = Join-Path $TestDrive 'invalid.jsonl'

        { Set-PoshUILogConfiguration -FilePath $path -MaximumSize 0 } | Should -Throw
        { Write-PoshUILog -Level Notice -Message 'invalid' } | Should -Throw
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}
