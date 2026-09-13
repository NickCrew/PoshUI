# Compose terminal output

PoshUI separates rendering from display so components can be nested, tested, redirected, or written by another host.

## Format without display effects

`Format-PoshUI*` commands return strings. They do not move the cursor or write directly to the host.

```powershell
$rows = @(
    [pscustomobject]@{ Service = 'API'; State = 'Ready' }
    [pscustomobject]@{ Service = 'Worker'; State = 'Starting' }
)

$table = $rows | Format-PoshUIDataTable -Property Service, State
$panel = $table | Format-PoshUIPanel -Title 'Release' -Width 48
$panel
```

This is the preferred boundary for tests, logs, files, and higher-level composition.

## Display through the runtime

`Show-PoshUI*` commands route output through the runtime mode selected for the current call:

```powershell
$rows | Show-PoshUIDataTable -Property Service, State
```

Rich mode preserves ANSI styling. Plain mode removes terminal sequences. Off mode suppresses display effects.

## Keep width explicit in automation

Terminal width can vary across local shells, CI jobs, and redirected output. Pass `-Width` when stable layout is part of the contract:

```powershell
'release ready' | Format-PoshUIBox -Title Status -Width 40
```

For exact signatures and pipeline behavior, use the [PowerShell reference](../reference/powershell.md).
