# Component library improvements

Status: Completed

Recorded: 2026-08-26

Completed: 2026-08-26

This is a historical implementation record. Its inventory and CI statements
describe the repository when the plan was completed and are not maintained as
the current contract. See the [PowerShell guide](../../../powershell/README.md),
[command reference](../../reference/powershell.md), and
[testing guide](../../testing/TESTING.md) for the supported API and platforms.

PoshUI already covers the expected terminal UI basics across nine feature
modules. The next useful increment is not another collection of isolated
commands. It is a smaller public API, a composable rendering contract, and
layout and data components that let the existing pieces work together.

## Evidence baseline

This assessment is based on the `master` checkout at `1124604`.

- The module documents 130 public functions and 26 underscore-prefixed
  internal functions across colors, logging, icons, progress, boxes, tables,
  prompts, menus, and charts.
- The manifest uses `FunctionsToExport = '*'`, and the root loader re-exports
  every function exported by each feature module. The underscore-prefixed
  internals therefore remain callable by consumers.
- PSScriptAnalyzer 1.25.0 produced no findings under the repository settings.
- A fresh Pester run executed 279 tests: 278 passed and 1 failed.
- The configured CI runtime covers Debian with PowerShell 7.4.19. It does not
  exercise Windows or macOS terminal behavior.

## Correctness work before expansion

### Preserve prompt configuration

`Prompts.psm1` assigns `PO_PROMPT_HISTORY_FILE` and
`PO_PROMPT_HISTORY_MAX` during import even when the caller set them first. The
off-mode runtime test supplies an isolated history path, but the import replaces
it with `$HOME/.posh-ui-history`. The test then observes the caller's existing
home history file and fails.

Completion criteria:

- Import preserves caller-supplied prompt settings.
- Defaults remain available when settings are absent.
- Off mode creates neither log nor prompt-history files.
- The full Pester suite passes from a clean checkout and a developer machine
  with an existing `$HOME/.posh-ui-history` file.

### Validate progress boundaries

`po_progress_bar` guards percentage calculation when `Total` is zero, then
divides by `Total` again while calculating filled width. Negative current
values and values beyond the total are not consistently clamped.

Completion criteria:

- `Total` and `Width` reject unsupported values with actionable errors.
- `Current` follows a documented clamp or validation policy.
- Tests cover zero, negative, over-complete, and minimum-width inputs in rich
  and plain modes.

### Protect password values

`po_prompt_password` builds and returns an immutable plaintext string. Define a
credential-input contract that avoids retaining secrets as ordinary strings
and document how callers consume and dispose of the result.

Completion criteria:

- The command does not return an ordinary plaintext string by default.
- Backspace, cancellation, redirected input, and empty input have explicit
  behavior and tests.
- Documentation does not encourage converting secrets back to plaintext.

## Architecture improvements

### Publish an explicit API

Remove underscore-prefixed helpers from the consumer command surface and
replace the wildcard manifest export with an explicit supported API. Optional
feature loading still needs a single source of truth so the manifest, loader,
tests, and documentation cannot drift independently.

Preserve existing public names for the current major version. A later naming
migration can introduce approved PowerShell verbs and PascalCase commands with
compatibility aliases and a published removal schedule.

Completion criteria:

- `Get-Command -Module PoshUI` returns only supported commands.
- Internal helpers remain callable inside their owning modules.
- One inventory drives export tests and generated command documentation.
- Removing an internal export does not break module-to-module dependencies.

### Separate formatting from terminal effects

Most components write directly to the host. That makes rendered output hard to
compose, capture, snapshot-test, redirect, or embed inside another component.
Adopt one contract across the library:

- Formatting functions return rendered lines or a small render model.
- Display functions own host and cursor effects.
- Interactive functions return typed result objects.
- Plain and off modes operate at the display boundary instead of being
  reimplemented by each component.

The final naming should follow PowerShell conventions. `Format-PoshUI*` and
`Show-PoshUI*` are working examples, not a decided API.

Completion criteria:

- Boxes, tables, and charts can render without writing to the host.
- Display wrappers reproduce the current visible output.
- Callers can compose two formatted components before displaying them.
- Snapshot tests cover rich and plain rendering.

### Resolve configuration once

Environment variables are useful startup inputs, but they should not remain the
library's mutable state store. Resolve them into module-scoped configuration,
theme, and component state objects during import. Tables, menus, and progress
displays should use independent instances so nested or concurrent usage does
not overwrite a singleton.

Completion criteria:

- Import does not overwrite caller-owned environment variables.
- Two table or progress instances can coexist without shared-state collisions.
- Theme values have primitive, semantic, and component layers.
- Environment variables remain documented compatibility inputs.

### Make commands PowerShell-native

Add advanced-function behavior, typed parameters, validation attributes,
pipeline input where it fits, standard error records, comment-based help, and
declared output types. Do this as commands are touched instead of generating a
large mechanical rewrite with no behavior proof.

## Component expansion

### 1. Layout

Add terminal-width-aware primitives for panels, vertical stacks, columns,
grids, padding, alignment, wrapping, and truncation. Layout should calculate a
render model before anything writes to the terminal.

This is the highest-value new module because dashboards and examples currently
repeat layout arithmetic that each component solves slightly differently.

### 2. Object data table

Accept pipeline objects and property selections directly. Support per-column
formatters, maximum widths, wrapping, truncation, sorting, and paging. Replace
delimiter-encoded rows and `.Split()` CSV parsing for structured inputs, since
those contracts cannot preserve colons, quoted delimiters, or embedded
newlines.

### 3. Live display region

Create one cursor owner that coordinates dashboards, progress indicators,
spinners, and log messages. It should guarantee cursor restoration through
success, cancellation, and exceptions, with a stable plain-mode transcript.

### 4. Tree and hierarchy view

Render deployment plans, repository trees, nested configuration, test results,
and dependency structures. Support expanded and compact styles with ASCII and
Unicode renderers.

### 5. Searchable selection

Add incremental filtering, keyboard navigation, cancellation, disabled
entries, typed values, and optional preview text. Menu actions should accept
scriptblocks or command metadata instead of only command-name strings.

### 6. Diff and code-block renderer

Support line numbers, additions, removals, context lines, wrapping, and stable
plain output. Color can improve scanning, but it cannot be the only difference
between states.

### 7. Stepper and timeline

Represent pending, active, successful, failed, and skipped stages for release,
deployment, and setup workflows. Build it on the layout and render contracts
rather than giving it independent cursor behavior.

## Verification investments

- Add behavior and golden-output coverage for each public component. Many
  current tests prove command availability or non-empty output without checking
  the rendered contract.
- Exercise rich, plain, off, redirected-output, redirected-input, narrow-width,
  and Unicode cases.
- Add Windows and macOS CI jobs for terminal and path behavior that Debian
  cannot prove.
- Generate command reference pages from the supported API inventory and
  comment-based help.
- Add compatibility tests before renaming or removing any public command.

## Delivered sequence

1. Repair prompt configuration and progress validation, then return the suite
   to green.
2. Decide and document the render, display, state, and export contracts.
3. Privatize internal helpers and establish the supported API inventory.
4. Implement Layout against the new render contract.
5. Implement the object data table and migrate one existing dashboard example.
6. Add the live display region before expanding animated components.
7. Implement the remaining components against the shared render and state
   contracts.

## Decision record

The work landed in two increments. The first repaired correctness defects and
established explicit export, render, display, state, and configuration
contracts. The second implemented all seven expansion components after that
foundation passed its local verification gates.

Assessment confidence at planning time was 95 percent. Windows and macOS jobs
now exist in CI for the terminal and path behavior that local macOS validation
cannot prove across platforms.

## Completion record

The foundation and expansion increments are implemented. The library preserves
prompt inputs, validates progress boundaries, returns password input as
`SecureString`, publishes an explicit 193-command API, and keeps underscore
helpers private. Configuration, themes, tables, menus, progress, live regions,
search selections, and steppers use independent typed state. Boxes, tables,
menus, charts, progress, layout, object data tables, trees, text views,
searchable selections, live regions, and steppers expose composable formatting
or display boundaries where terminal effects apply.

All seven expansion items are present:

1. Layout provides panels, stacks, columns, grids, padding, alignment,
   grapheme-aware wrapping, and truncation.
2. Object data tables accept pipeline objects and property definitions, retain
   delimiter and embedded-newline data, and support formatters, width limits,
   sorting, and paging.
3. Live regions coordinate keyed dashboard, progress, spinner, log, and custom
   content through one cursor owner with plain and off fallbacks.
4. Tree views render nested objects and collections in compact or expanded
   ASCII and Unicode forms, including bounded depth and circular references.
5. Searchable selection provides incremental filtering, navigation,
   cancellation, disabled entries, typed values, previews, and typed menu
   actions through scriptblocks or command metadata.
6. Text views render code blocks and semantic diffs with line numbers, context,
   state markers, and grapheme-aware wrapping.
7. Steppers represent pending, active, successful, failed, and skipped stages
   using the shared layout contract without owning cursor state.

The release-console demo now uses structured object data tables and a stepper.
The command reference is generated from the manifest inventory and authored
help. Local verification covers root loading, optional module toggles, minimal
mode, command contracts, pipeline composition, rich and plain rendering,
off-mode effects, redirected input and output, narrow and Unicode content,
state isolation, cursor cleanup, compatibility behavior, reference drift, and
static analysis.
