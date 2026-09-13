# Testing PoshUI

The repository pins PowerShell 7.6.4, Pester 6.0.1, and PSScriptAnalyzer 1.25.0. Run tests from the repository root:

```powershell
make bootstrap
pwsh ./build.ps1 -Task test
```

Or invoke the suite directly:

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File ./powershell/tests/Invoke-Tests.ps1
```

The suite covers:

- the exact 82-command manifest export contract;
- advanced-function metadata and authored help;
- rich, plain, and off runtime behavior;
- complete environment preservation during import;
- composable layout, box, table, chart, tree, code, diff, and progress rendering;
- native prompt behavior under redirected input;
- searchable selection, steppers, and live-region cursor coordination;
- JSONL logging, filtering, sanitization, rotation, retention, `ShouldProcess`, and file safety;
- versioned installer layout and runtime-only package contents;
- PowerShell 7.6 policy across source and CI;
- generated full-reference freshness and local documentation links;
- release classification, changelog preparation, and publication guards.

CI runs the suite on Linux and Windows. macOS is manually qualified because no macOS runner is currently available.

## Static analysis

```powershell
pwsh ./build.ps1 -Task lint
```

PSScriptAnalyzer findings are treated as failures. Private helpers use approved PowerShell verbs and an `Internal` noun suffix where they cross module boundaries.

## Reference and release checks

```powershell
pwsh ./build.ps1 -Task docs-check
pwsh ./build.ps1 -Task version-check
pwsh ./build.ps1 -Task release-plan
```

The documentation check imports the requested manifest by path, inspects that exact module object, and compares the complete generated reference directory. Release stamping regenerates the command reference before the release commit.
