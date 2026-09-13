# PoshUI PowerShell module

PoshUI provides 82 native advanced functions for terminal UI composition, interaction, and structured local logging. It requires PowerShell Core 7.6 or later and has no runtime dependencies.

## Installation

From a registered PSResource repository:

```powershell
Install-PSResource PoshUI
Import-Module PoshUI
```

From a checkout:

```powershell
Import-Module ./powershell/PoshUI.psd1
```

The published package uses the standard `PoshUI/<version>` module layout and stages only `PoshUI.psd1`, `PoshUI.psm1`, `README.md`, and `modules/`. Repository-only assets such as `bin/`, `examples/`, `tests/`, and `tools/` are not included in installed packages.

## Composition model

`Format-PoshUI*` commands return strings. `Show-PoshUI*` commands own display effects:

```powershell
$status = Format-PoshUIStatus -Kind Success -Text Ready
$panel = $status | Format-PoshUIPanel -Title Deployment -Width 40
$panel | ForEach-Object { $_ }
```

For status output, compose it into a box or write it through another display component:

```powershell
Format-PoshUIStatus Success Ready |
    Show-PoshUIBox -Title Deployment -Style Rounded
```

## Runtime modes

`POSH_UI_MODE` is read at runtime:

- `rich`: ANSI styling and terminal control when available.
- `plain`: stable ANSI-free text.
- `off`: no host or logging effects.
- unset: automatic selection based on the host, redirection, and CI state.

Feature toggles use `POSH_UI_LOAD_<FEATURE>=false` and are read during import. All other configuration is module-owned. Import preserves the complete process environment.

`Get-PoshUIRuntime` reports the selected mode, selection reason, stream redirection, interactive-input availability, and terminal-control support.

## Themes

The default theme is active out of the box. `Set-PoshUITheme` switches built-in themes while the module is loaded:

```powershell
Set-PoshUITheme -Name light
Set-PoshUITheme -Name default
```

For a custom theme, create an independent value, change its layered tokens, and activate it:

```powershell
$theme = New-PoshUITheme -Name default
$theme.Component.Table.Header = "`e[1;38;2;173;232;58m"
$theme | Set-PoshUITheme
```

## Prompts

The native prompt commands are:

- `Read-PoshUIText`
- `Read-PoshUIPassword`
- `Confirm-PoshUIChoice`
- `Select-PoshUIOption`
- `Select-PoshUIMultipleOption`
- `Read-PoshUINumber`
- `Read-PoshUIFilePath`
- `Read-PoshUIDirectoryPath`

Redirected input returns explicit defaults where available, returns a safe negative result for confirmation, or throws an actionable error. Password input returns a read-only `SecureString`. Prompt history is not stored.

## Local JSONL sink

```powershell
Set-PoshUILogConfiguration -Level Debug -FilePath ./logs/app.jsonl -ConsoleOutput $false
Write-PoshUILog -Level Info -Message started -Data @{ process = $PID }
Clear-PoshUILog -WhatIf
```

Each accepted event is serialized as one UTF-8 JSON line with `schemaVersion = 1`. A path-derived named mutex coordinates appends and size-based rotation across PowerShell processes. Retention is controlled by `MaximumSize` and `MaximumFiles`. Fatal is a log level and does not terminate the caller. Structured `Data` is written verbatim, so it must not contain credentials.

## Supported platforms

Windows and Linux are covered by CI. macOS is supported and manually qualified, with the same PowerShell 7.6 minimum, but no macOS CI runner is currently available.

## Repository development

The CLI and examples are checkout-only utilities:

```powershell
./powershell/bin/posh-ui.ps1 validate
./powershell/bin/posh-ui.ps1 demo -Auto
./powershell/bin/posh-ui.ps1 benchmark -Iterations 0.01
```

Tests require Pester 6.0.1. CI qualifies PowerShell 7.6.4. `build.ps1` uses the current PowerShell executable and installs the exact development-module versions.

The complete supported API is in [the generated command reference](../docs/reference/powershell.md).
