# JSONL logging

PoshUI includes an optional dependency-free local sink. It writes one UTF-8 JSON object per line and does not require a logging module.

## Configure the sink

```powershell
Set-PoshUILogConfiguration `
    -Level Info `
    -FilePath ./logs/application.jsonl `
    -ConsoleOutput $false `
    -MaximumSize 10MB `
    -MaximumFiles 5
```

Write an event with structured data:

```powershell
Write-PoshUILog -Level Info -Message 'deployment complete' -Data @{
    environment = 'stage'
    version = '26.8.3'
}
```

Each event includes `schemaVersion`, `timestamp`, `level`, `message`, and optional `data` or exception details. The current schema version is `1`.

## Rotation and concurrency

Rotation occurs before an accepted event would exceed `MaximumSize`. PoshUI retains the configured number of rotated files. A named mutex derived from the canonical path coordinates append and rotation operations across PowerShell processes using the same sink.

## Safety boundaries

- PoshUI removes terminal control sequences from the message.
- Structured `Data` is serialized verbatim. Do not include passwords, tokens, or other credentials.
- `Fatal` is a log level. It does not terminate the caller.
- Off mode suppresses logging effects.
- `Clear-PoshUILog` supports `-WhatIf` and confirmation.

Inspect or clear the current configuration:

```powershell
Get-PoshUILogConfiguration
Clear-PoshUILog -WhatIf
```

See the [PowerShell reference](../reference/powershell.md) for the complete logging command contracts.
