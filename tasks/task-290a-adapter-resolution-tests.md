# Task 290a — Adapter Resolution Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

A code audit found the v2.2 Project Discipline subsystem is ~half dead code. `DisciplineEngine`
is built with `ProjectAdapter.makeStub(language:"swift")` (`AppState.swift:120`) and the
`AdapterRegistry` loaded at launch is never read — so the engine never uses a project's real
adapter. This is unit A1 of the wiring plan.

New surface introduced in task 290b:
  - `DisciplineEngine.setAdapter(_:)` — replace the engine's adapter at runtime
  - `DisciplineEngine.currentAdapter()` — read the engine's current adapter
  - `DisciplineEngine.resolveProjectAdapter(projectPath:registry:)` — static; loads
    `.merlin/project.toml`, resolves the adapter from the registry, falls back to the stub

TDD coverage:
  `MerlinTests/Unit/DisciplineAdapterResolutionTests.swift` — setAdapter updates the engine;
  resolveProjectAdapter returns the stub with no config, the configured adapter when present,
  and the stub when the configured adapter key is unknown.

## Write to: MerlinTests/Unit/DisciplineAdapterResolutionTests.swift
(see committed file)

## Verify
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
Expected: BUILD FAILED — missing `setAdapter`, `currentAdapter`, `resolveProjectAdapter`.

## Commit
git add MerlinTests/Unit/DisciplineAdapterResolutionTests.swift tasks/task-290a-adapter-resolution-tests.md
git commit -m "Task 290a — Adapter resolution tests (failing)"
