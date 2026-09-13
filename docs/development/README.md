# Development

The repository task graph is implemented in `build.ps1`. It uses the `pwsh`
executable from the environment and does not manage the PowerShell runtime.

```sh
make bootstrap
pwsh ./build.ps1 -Task check
```

Focused tasks include:

| Task | Purpose |
| --- | --- |
| `pwsh ./build.ps1 -Task lint` | Run the repository PSScriptAnalyzer policy. |
| `pwsh ./build.ps1 -Task test` | Run the complete Pester suite. |
| `pwsh ./build.ps1 -Task docs` | Regenerate `docs/reference`. |
| `pwsh ./build.ps1 -Task docs-check` | Fail when generated reference files are stale. |
| `pwsh ./build.ps1 -Task version-check` | Verify generated version sites. |
| `pwsh ./build.ps1 -Task release-plan` | Preview the next semantic version. |

The documentation generator imports the exact manifest by path and uses its explicit export inventory. Update comment-based help and regenerate the reference in the same change as any public command contract. Release stamping also regenerates the reference after changing the manifest version.

Contribution and merge request expectations are in [CONTRIBUTING.md](../../CONTRIBUTING.md). Detailed test coverage is in [Testing PoshUI](../testing/TESTING.md).
