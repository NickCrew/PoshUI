# Contributing to PoshUI

PoshUI uses Conventional Commits and squash merges. Keep a change focused enough that its merge request title can describe the resulting commit.

## Set up the repository

Install PowerShell 7.6 or later, then install the pinned development modules:

```sh
make bootstrap
```

The build uses the `pwsh` executable from the environment. `build.ps1` owns the
repository task graph and does not install or select a PowerShell runtime.

## Verify a change

Run the full local gate before opening a merge request:

```sh
pwsh ./build.ps1 -Task check
```

Run `pwsh ./build.ps1` to see focused lint, test, documentation, version, and release commands. Run `pwsh ./build.ps1 -Task docs` whenever public comment-based help or the manifest inventory changes. CI rejects stale generated reference files. Add behavior-focused Pester coverage when a change introduces or repairs observable behavior.

## Merge requests

Use a Conventional Commit title such as `fix(rendering): preserve emoji width`. Early in the project, CODEOWNERS identifies likely maintainers but does not substitute for an available reviewer. Explain the intended outcome, the relevant behavior, the checks run, and any known gap in the merge request description.

Add user-visible notes under `## [Unreleased]` in `CHANGELOG.md`. Merge-request
pipelines report the semantic version implied by the squash without changing or
publishing anything. After a releasable squash reaches `master`, CI stamps every
version site, rolls curated notes into a dated section, atomically pushes the
release commit and tag, publishes the module, and creates the GitLab Release.
Releasable Conventional Commits supply fallback notes when Unreleased is empty.
The `release-plan` and `release-apply` build tasks remain available
for local preview and rehearsal, not as required release steps.
