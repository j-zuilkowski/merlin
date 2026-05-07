# Phase 174a — LoRAProviderRoutingTests: wrong slot mapping (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 173b complete: ConversationHTMLRenderer fenced code fix.

## Problem

Three `LoRAProviderRoutingTests` tests fail because the tests call the GLOBAL
`makeEngine(proProvider:flashProvider:)` from `TestHelpers/EngineFactory.swift`,
which maps:
  - `proProvider → .reason` slot
  - `flashProvider → .execute` slot

But the LoRA tests expect:
  - `proProvider → .execute` slot  (the "main" model that LoRA overrides)
  - `flashProvider → .reason` slot

So `engine.provider(for: .execute)` returns the flash mock instead of the pro mock,
and `engine.provider(for: .reason)` returns the pro mock instead of flash.

Failing tests:
- `testExecuteSlotFallsBackToProProviderWhenLoRANil`
- `testReasonSlotAlwaysUsesFlashProvider`
- `testClearingLoRAProviderRestoresProProvider`

Root cause: `LoRAProviderRoutingTests.swift` uses the global `makeEngine` from
`EngineFactory.swift` which has the slots inverted relative to what these tests expect.

## Existing test file

`MerlinTests/Unit/LoRAProviderRoutingTests.swift` — already committed.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRAProvider.*failed|BUILD' | head -10
```

Expected: 3 LoRAProviderRoutingTests failures.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add phases/phase-174a-lora-routing-tests.md
git commit -m "Phase 174a — LoRAProviderRoutingTests slot-mapping failures documented"
```
