# Changelog

All notable changes to PoshUI are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Add user-visible notes under Unreleased while changes land. Release preparation
moves curated notes into the dated version section. If Unreleased is empty,
releasable Conventional Commits provide fallback notes.

## [Unreleased]

## [4.1.0] - 2026-08-28

### Added

- Added `Get-PoshUIRuntime` for inspecting mode selection and terminal capabilities.
- Added `schemaVersion = 1` to every JSONL log event.
- Added full generated PowerShell reference documentation with drift checking.

### Changed

- Made the Unanet theme the default and added runtime switching for built-in and custom themes.

## [4.0.0] - 2026-08-27

### Added

- Added cross-process coordination for JSONL appends, rotation, and log clearing.

### Changed

- Replaced the compatibility surface with an explicit 80-command native PowerShell API.
- Raised the minimum runtime to PowerShell Core 7.6 and pinned development and CI to PowerShell 7.6.4.
- Changed installation and publication to use the standard versioned module layout with a runtime-only package.
- Made runtime configuration module-owned and prevented automatic interactive input in CI.

### Removed

- Removed the legacy `po_*` and `posh_ui_*` command families and underscore-prefixed helper exports.
- Removed repository tools, tests, examples, and the CLI from the published package.

### Fixed

- Sanitized untrusted terminal control sequences while preserving PoshUI formatting in rich mode.
- Made destructive log clearing honor PowerShell confirmation and `WhatIf` behavior.

## [3.0.1] - 2026-08-27

### Changed

- fix(ci): configure gitlab release host (533ca303)

## [3.0.0] - 2026-08-27

### Added

- Added a dependency-free, synchronous UTF-8 JSONL file sink with structured event data, severity filtering, and size-based rotation.
- Added native header, subheader, and semantic status formatting commands.
- Added layout, object data table, live region, tree, searchable selection, text view, and stepper components.
- Added typed menu action invocation for scriptblocks, command metadata, and exact command names.
- Added composable format and display commands for boxes, tables, charts, and progress.
- Added independent table, menu, progress, configuration, and layered theme models.
- Added generated reference documentation and Windows and macOS CI coverage.

### Changed

- Replaced the legacy logging command family with four native PowerShell commands. This is a breaking API change.
- Replaced wildcard exports with an explicit 183-command supported API.
- Made every supported command an advanced PowerShell function and added authored help for the new architecture commands.
- Migrated the release-console demo to structured object data tables and the shared stepper model.
- Changed `po_prompt_password` to return a read-only `SecureString`.

### Fixed

- Rebuilt empty rich-mode presentation tokens inherited from a plain parent process.
- Preserved caller-owned prompt and configuration environment values during import.
- Validated and clamped progress boundaries consistently in rich and plain modes.

## [2.3.0] - 2026-08-26

### Changed

- fix(menu): keep actions in menu (591bf601)
- fix(dashboard): wait before returning (7f03b3ff)
- feat(examples): expand release console demo (11246047)

## [2.2.2] - 2026-08-24

### Changed

- fix(release): query packages via client (950ef4c6)

## [2.2.1] - 2026-08-24

### Changed

- fix(release): use JFrog lookup feed (eaf35d06)

## [2.2.0] - 2026-08-24

### Changed

- feat(release): add verified changelog notes (b4361c0a)
- feat(release): automate publication (0f007c0a)
- fix(ci): install git for PowerShell jobs (22c882c6)

## [2.1.1] - 2026-08-23

### Changed

- Established PoshUI as a versioned PowerShell module published from semantic
  version tags.

[Unreleased]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v4.1.0...HEAD
[4.1.0]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v4.0.0...v4.1.0
[4.0.0]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v3.0.1...v4.0.0
[3.0.1]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v3.0.0...v3.0.1
[3.0.0]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v2.3.0...v3.0.0
[2.3.0]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v2.2.2...v2.3.0
[2.2.2]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v2.2.1...v2.2.2
[2.2.1]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v2.2.0...v2.2.1
[2.2.0]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/compare/v2.1.1...v2.2.0
[2.1.1]: https://gitlab.unanet.io/cosential/dev-tools/posh-ui/-/tags/v2.1.1
