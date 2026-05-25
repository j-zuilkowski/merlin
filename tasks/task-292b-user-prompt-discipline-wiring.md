# Phase 292b — User-Prompt Discipline Wiring (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 292a complete: failing test in `UserPromptDisciplineWiringTests`.
Unit A3 of the discipline-wiring plan.

## Edit: Merlin/Engine/AgenticEngine.swift
After `hookEngine.runUserPromptSubmit`, `send` now calls
`UserPromptDisciplineChecker().check(prompt:projectPath:)` when a project path is set.
On `.missingPhaseFile` it yields `.systemNote("⚠️ TDD discipline: …")`, so an unscoped
feature request is visible in the agent loop.

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/UserPromptDisciplineWiringTests
Expected: BUILD SUCCEEDED, both tests pass.

## Commit
git add Merlin/Engine/AgenticEngine.swift tasks/task-292b-user-prompt-discipline-wiring.md
git commit -m "Phase 292b — User-prompt discipline wiring"
