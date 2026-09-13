# Runtime modes

PoshUI resolves terminal capabilities at call time. Set `POSH_UI_MODE` when a script needs a deterministic output policy.

| Mode | Behavior |
| --- | --- |
| `auto` or unset | Select rich or plain output from host, stream, terminal, CI, and color signals. |
| `rich` | Preserve ANSI styling and use terminal control when the host supports it. |
| `plain` | Return and display stable text without ANSI control sequences. |
| `off` | Suppress PoshUI display and logging effects. |

## Inspect the current decision

```powershell
Get-PoshUIRuntime | Format-List
```

The result explains the requested mode, selected mode, selection reason, redirection state, interactive-input availability, and terminal-control support.

## Make automation deterministic

Use plain mode for logs, snapshots, and redirected command output:

```powershell
$env:POSH_UI_MODE = 'plain'
Import-Module PoshUI
Show-PoshUIBox -Content 'deployment ready' -Width 32
```

Use off mode when a caller needs to silence both UI and PoshUI logging effects:

```powershell
$env:POSH_UI_MODE = 'off'
```

The mode is read at runtime, so a process can change it after importing the module. Feature toggles are different: `POSH_UI_LOAD_<FEATURE>` values are read during import.
