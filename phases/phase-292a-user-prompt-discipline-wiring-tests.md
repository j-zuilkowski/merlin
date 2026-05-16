# Phase 292a — User-Prompt Discipline Wiring Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit A3 of the discipline-wiring plan. `UserPromptDisciplineChecker` is unit-tested but
never called by the agent loop.

New behaviour in phase 292b (no new public API — pure wiring):
  `AgenticEngine.send` runs `UserPromptDisciplineChecker.check` after `runUserPromptSubmit`
  and yields a `.systemNote` ("⚠️ TDD discipline: …") when the prompt is an unscoped
  feature request.

TDD coverage:
  `MerlinTests/Unit/UserPromptDisciplineWiringTests.swift` — a feature-request prompt with
  no phase file emits the note; a bug-fix prompt does not.

## Write to: MerlinTests/Unit/UserPromptDisciplineWiringTests.swift
(see committed file)

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/UserPromptDisciplineWiringTests
Expected: BUILD SUCCEEDED, `testFeatureRequestWithoutPhaseFileEmitsDisciplineNote` FAILS
(no note emitted yet); `testBugFixPromptEmitsNoDisciplineNote` passes.

## Commit
git add MerlinTests/Unit/UserPromptDisciplineWiringTests.swift phases/phase-292a-user-prompt-discipline-wiring-tests.md
git commit -m "Phase 292a — User-prompt discipline wiring tests (failing)"
