# Task 489: synchronize Developer Manual with current source tree

## Goal

Update `Merlin/Docs/DeveloperManual.md` and stale source comments so contributor
documentation matches the current engine, tool, discipline, runtime, and
electronics source tree.

## Fail-first evidence

Added
`DocumentationSweepTests.testDeveloperManualMatchesCurrentEngineToolAndElectronicsSurfaces`.
Before the manual/comment updates, the focused test failed with 47 failures:
missing current surfaces such as `slotAssignments`, `ProviderRegistry`,
`Merlin/Discipline/DisciplineEngine.swift`, current app/UI/Xcode tool names,
current KiCad workflow tools, and current electronics statuses; stale surfaces
such as `proProvider`, `xcode_open_simulator`, `ax_inspect`,
`kicad_create_project`, and `kicad_release_approval` were still present.

## Completed changes

- Updated the repository layout section for `Merlin/CAG`, `Merlin/Discipline`,
  `Merlin/Electronics`, `Merlin/Plugins`, and `Merlin/Runtime`.
- Replaced stale `AgenticEngine` provider ownership and run-loop text with the
  slot/provider-registry model used by current source.
- Corrected `DisciplineEngine` paths from `Merlin/Engine` to
  `Merlin/Discipline`.
- Replaced stale built-in tool names with current `ToolDefinitions` names.
- Replaced stale electronics tool/status tables with the current
  `KiCadToolDefinitions` workflow and evidence-gated status contract.
- Updated code-map cross references for discipline, runtime, and electronics
  source files.
- Updated stale code comments in `AgenticEngine.runLoop` and
  `ToolDefinitions`.

## Focused verification

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/DocumentationSweepTests/testDeveloperManualMatchesCurrentEngineToolAndElectronicsSurfaces -derivedDataPath /tmp/merlin-derived-task489-docs
```

Result: selected test passed, 1 test, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/DocumentationSweepTests -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests -derivedDataPath /tmp/merlin-derived-task489-docs
```

Result: selected documentation sweeps passed, 16 tests, 0 failures.
