# Phase 197a — Stable Prefix Cache Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 196b complete: session restore dedup + history loading.

## Problem
`AgenticEngine.buildSystemPrompt()` is a `private` method called on every loop iteration.
It rebuilds the full system prompt string from scratch — including constitution.md content,
memories, permission mode, working directory, and the static core prompt — even when none
of those inputs have changed. The only part that legitimately varies mid-loop is
`nearCeilingWarningAddendum`.

llama.cpp (LM Studio) uses prefix matching to reuse KV cache across requests. For the cache
to hit, the prefix of the system message must be byte-identical between turns. Rebuilding the
string each turn does not guarantee this; caching the stable portion makes it an explicit
guarantee.

## New surface in phase 197b
- `AgenticEngine.buildStablePrefix() -> String` — internal; returns the cacheable portion
  of the system prompt (everything except `nearCeilingWarningAddendum`)
- `AgenticEngine._stablePrefixDirty: Bool` — internal; true when the cache must be rebuilt
- `AgenticEngine.constitutionContent` gains `didSet { _stablePrefixDirty = true }`
- `AgenticEngine.memoriesContent` gains `didSet { _stablePrefixDirty = true }`
- `AgenticEngine.standingInstructions` gains `didSet { _stablePrefixDirty = true }`
- `AgenticEngine.permissionMode` gains `didSet { _stablePrefixDirty = true }`
- `AgenticEngine.currentProjectPath` gains `didSet { _stablePrefixDirty = true }`
- `AgenticEngine.buildSystemPrompt()` uses cached stable prefix + appends
  `nearCeilingWarningAddendum` only when present

TDD coverage:
  File — StablePrefixCacheTests.swift: 5 tests

---

## Write to: MerlinTests/Unit/StablePrefixCacheTests.swift

```swift
// StablePrefixCacheTests.swift
// Phase 197a — failing tests for stable system-prompt prefix caching.
import XCTest
@testable import Merlin

@MainActor
final class StablePrefixCacheTests: XCTestCase {

    private func makeEngine() -> AgenticEngine {
        AgenticEngine()
    }

    // MARK: - Cache hit

    /// Two consecutive calls to buildStablePrefix() with unchanged state must return
    /// the same string.
    /// FAILS before 197b — buildStablePrefix() does not exist.
    func test_stablePrefix_isSameAcrossConsecutiveCalls() {
        let engine = makeEngine()
        engine.constitutionContent = "# Instructions\nDo stuff."
        let first = engine.buildStablePrefix()
        let second = engine.buildStablePrefix()
        XCTAssertEqual(first, second)
    }

    // MARK: - Cache invalidation

    /// Changing constitutionContent must cause the next buildStablePrefix() call to
    /// return a different string.
    /// FAILS before 197b — _stablePrefixDirty / buildStablePrefix() do not exist.
    func test_stablePrefix_changesWhenConstitutionContentChanges() {
        let engine = makeEngine()
        engine.constitutionContent = "v1"
        let first = engine.buildStablePrefix()
        engine.constitutionContent = "v2"
        let second = engine.buildStablePrefix()
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.contains("v2"))
    }

    /// Changing memoriesContent must invalidate the cache.
    func test_stablePrefix_changesWhenMemoriesContentChanges() {
        let engine = makeEngine()
        engine.memoriesContent = "mem-A"
        let first = engine.buildStablePrefix()
        engine.memoriesContent = "mem-B"
        let second = engine.buildStablePrefix()
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.contains("mem-B"))
    }

    /// Changing standingInstructions must invalidate the cache.
    func test_stablePrefix_changesWhenStandingInstructionsChange() {
        let engine = makeEngine()
        engine.standingInstructions = "always use emoji"
        let first = engine.buildStablePrefix()
        engine.standingInstructions = "never use emoji"
        let second = engine.buildStablePrefix()
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Dynamic suffix

    /// nearCeilingWarningAddendum must appear in buildSystemPrompt() but NOT in
    /// buildStablePrefix() — it is always appended fresh to preserve per-iteration accuracy.
    /// FAILS before 197b — buildStablePrefix() does not exist.
    func test_nearCeilingWarning_appearsInSystemPromptNotStablePrefix() {
        let engine = makeEngine()
        engine.nearCeilingWarningAddendum = "[Warning: near ceiling]"
        let stable = engine.buildStablePrefix()
        let full = engine.buildSystemPromptForTesting()
        XCTAssertFalse(stable.contains("[Warning: near ceiling]"),
                       "stable prefix must not include the near-ceiling warning")
        XCTAssertTrue(full.contains("[Warning: near ceiling]"),
                      "full system prompt must include the near-ceiling warning")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `buildStablePrefix()`, `buildSystemPromptForTesting()`, and
`_stablePrefixDirty` do not exist yet.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/StablePrefixCacheTests.swift
git commit -m "Phase 197a — StablePrefixCacheTests (failing)"
```
