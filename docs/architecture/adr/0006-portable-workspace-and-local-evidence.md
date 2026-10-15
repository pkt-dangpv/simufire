# ADR 0006: Portable workspaces and archived local evidence

## Status

Accepted, 2026-10-14.

## Context

The same project is checked out on two Windows computers, on different drives.
OneDrive also copied generated artifacts and duplicate source files into the tree.
Historical diagnostics ignored by filename can be cited in published documents
without being available in a fresh checkout.

## Decision

- Resolve project paths from the script location, using `pathlib` or `$PSScriptRoot`.
- Discover Godot through an explicit argument, `GODOT_EXE`, PATH or this machine's
  Desktop. `scripts/project_paths.py` and `scripts/project_paths.ps1` provide the
  shared candidates; no username or drive letter is embedded in discovery.
- Keep machine configuration local; do not share a desktop executable path through Git.
- Archive redundant copies outside the project and OneDrive, with original relative
  paths, SHA-256 values and a journal. Preserve originals tracked by Git.
- Preserve historical experiments as a documented, checksummed archive under
  `docs/archive/`. The archive is evidence, not a newly approved scientific baseline.
- Keep historical log bytes, including recorded absolute paths, unchanged. Such paths
  describe the originating run; executable code must not depend on those paths.

## Consequences

The drive containing the repository does not determine where Godot is installed.
A fresh checkout can retrieve preserved experiments without enabling them in the
official validation corpus. Archive manifests permit independent verification.
An archive on one computer is not automatically a backup on the other computer.
