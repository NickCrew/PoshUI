# Getting started

This guide imports PoshUI and renders a small deployment status without requiring an interactive terminal.

## Prerequisites

- PowerShell 7.6 or later.
- A registered repository containing PoshUI, or a local checkout.

## Install and import

Install from a registered PSResource repository:

```powershell
Install-PSResource PoshUI
Import-Module PoshUI
```

From a checkout, import the manifest directly:

```powershell
Import-Module ./powershell/PoshUI.psd1
```

Verify the import and inspect the selected terminal behavior:

```powershell
Get-Module PoshUI
Get-PoshUIRuntime | Format-List Mode, Reason, Color, TerminalControl
```

## Render a component

Format a semantic status, then compose it into a box:

```powershell
$status = Format-PoshUIStatus -Kind Success -Text 'API ready'
$status | Show-PoshUIBox -Title 'Deployment' -Style Rounded -Width 40
```

Use a formatter when another command needs the rendered strings. Use a `Show-PoshUI*` command when PoshUI should own the terminal output.

## Next steps

- [Compose terminal output](composition.md)
- [Select a runtime mode](runtime-modes.md)
- [Use or customize a theme](themes.md)
- [Browse every command](../reference/powershell.md)
