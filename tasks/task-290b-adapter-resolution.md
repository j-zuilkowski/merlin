# Phase 290b — Adapter Resolution (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 290a complete: failing tests in `DisciplineAdapterResolutionTests`.

Unit A1 of the discipline-wiring plan. `DisciplineEngine` was built with
`ProjectAdapter.makeStub`; the `AdapterRegistry` loaded at launch was never read.

## Edit: Merlin/Discipline/DisciplineEngine.swift
- `adapter` changed from `let` to `var`.
- Added `setAdapter(_:)` — replace the adapter at runtime (actor-isolated).
- Added `currentAdapter()` — read the current adapter.
- Added static `resolveProjectAdapter(projectPath:registry:)` — loads
  `.merlin/project.toml` via `ProjectConfigLoader`, resolves the adapter key through
  `AdapterRegistry`, falls back to the Swift stub when no config / unknown key.

## Edit: Merlin/App/AppState.swift
The init Task that installs + loads seed adapters now also calls
`DisciplineEngine.resolveProjectAdapter` and applies the result via `setAdapter`, so
the engine scans with the project's real adapter instead of the bootstrap stub.

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/DisciplineAdapterResolutionTests
Expected: BUILD SUCCEEDED, 4 tests pass.

## Commit
git add Merlin/Discipline/DisciplineEngine.swift Merlin/App/AppState.swift \
  tasks/task-290b-adapter-resolution.md
git commit -m "Phase 290b — Adapter resolution"
