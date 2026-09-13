# Architecture

PoshUI is a dependency-free PowerShell module built around composable text rendering and one shared terminal runtime boundary.

## Module loading

`powershell/PoshUI.psm1` imports the runtime first, resolves feature toggles, then imports the enabled feature modules. The manifest is the public API inventory. A nested module can export helpers to sibling modules, but the root loader admits only names listed in `FunctionsToExport`.

Feature toggles use `POSH_UI_LOAD_<FEATURE>=false` and are resolved at import. Minimal mode disables the larger layout and interaction features while preserving the core runtime and formatting surface.

## Rendering boundary

`Format-PoshUI*` commands return composable strings and do not own display effects. `Show-PoshUI*` commands pass those strings through the shared runtime boundary. That boundary resolves rich, plain, or off behavior at call time, so changing `POSH_UI_MODE` after import does not leave stale capability state behind.

Themes follow the same pattern. Feature modules retain a shared style object, and `Set-PoshUITheme` updates that object in place. Existing modules therefore observe a theme switch without being reimported.

## State ownership

Configuration, active theme, prompt behavior, live regions, and logging settings remain in module scope. Import preserves the process environment. `Get-PoshUIConfiguration` returns an independent snapshot rather than a mutable reference to module state.

## Packaging boundary

The published package contains only the module manifest, root module, module README, and feature modules. Tests, examples, the repository CLI, generated reference documentation, and release tooling remain checkout-only assets.

See the [composition guide](../guides/composition.md), [runtime modes](../guides/runtime-modes.md), and [generated reference](../reference/powershell.md) for the public contracts built on these boundaries.
