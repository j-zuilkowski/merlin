# Phase 206a — LLM Summarisation Compaction Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 205b complete: `compactIfNeededMidLoop()` wired in the execute loop.

New surface introduced in phase 206b:
  - `ContextManager.compact(force: Bool, customDigest: String?)` — private; existing `compact(force:)` gains an optional `customDigest` parameter (default `nil`). When non-nil, `customDigest` replaces the auto-generated preview string in the summary system message.
  - `ContextManager.compactWithSummaryIfNeeded(provider: any LLMProvider) async -> Bool` — checks `estimatedTokens > midLoopCompactionThreshold`; if exceeded, extracts the text of removable exchange groups, calls the provider for a one-shot narrative summary (no tools, temperature 0), then calls `compact(force: true, customDigest: summary)`; returns `true` when compaction fired. Falls back to the static sentinel on provider error.
  - `AgenticEngine.runLoop()` — replaces the `context.compactIfNeededMidLoop()` call (added in 205b) with `_ = await context.compactWithSummaryIfNeeded(provider: provider)`. The `provider` local variable (resolved execute-slot provider) is already in scope at that point.

TDD coverage:
  File 1 — LLMSummarisationCompactionTests: provider called above threshold, not called below, summary text appears in context, fallback on provider error, compactionCount increments, returns correct Bool

---

## Write to: MerlinTests/Unit/LLMSummarisationCompactionTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class LLMSummarisationCompactionTests: XCTestCase {

    // MARK: - Helpers

    /// Appends enough content to exceed `midLoopCompactionThreshold` (which we override to 2 000).
    private func appendBulkContent(_ cm: ContextManager, count: Int = 4) {
        for i in 0..<count {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "z", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
    }

    private func makeContextAboveThreshold() -> ContextManager {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 2_000   // low so tests stay fast
        appendBulkContent(cm)                   // ~4 000 tokens > 2 000
        return cm
    }

    // MARK: - Below threshold: provider must not be called

    func test_compactWithSummaryIfNeeded_does_not_call_provider_when_below_threshold() async {
        let provider = MockProvider(response: "summary text")
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 100_000   // very high; never reached
        cm.append(Message(role: .user, content: .text("hello"), timestamp: Date()))

        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertFalse(fired, "must return false when below threshold")
        XCTAssertEqual(provider.callCount, 0, "provider must not be called when below threshold")
    }

    // MARK: - Above threshold: provider is called

    func test_compactWithSummaryIfNeeded_calls_provider_when_above_threshold() async {
        let provider = MockProvider(response: "did: read Engine.swift, patched runLoop, tests passed")
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(provider.callCount, 1, "provider must be called exactly once for summarisation")
    }

    func test_compactWithSummaryIfNeeded_returns_true_when_fired() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()

        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertTrue(fired)
    }

    // MARK: - Summary text appears in context

    func test_compactWithSummaryIfNeeded_inserts_llm_summary_as_system_message() async {
        let summaryText = "Summarised: read 3 files, wrote Engine.swift, ran tests — all passed."
        let provider = MockProvider(response: summaryText)
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        let found = cm.messages.contains { msg in
            guard msg.role == .system else { return false }
            if case .text(let t) = msg.content { return t.contains(summaryText) }
            return false
        }
        XCTAssertTrue(found, "the provider's summary text must appear verbatim in a system message")
    }

    // MARK: - compactionCount increments

    func test_compactWithSummaryIfNeeded_increments_compactionCount() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()
        let before = cm.compactionCount

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(cm.compactionCount, before + 1)
    }

    // MARK: - Token reduction

    func test_compactWithSummaryIfNeeded_reduces_estimatedTokens() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()
        let tokensBefore = cm.estimatedTokens

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertLessThan(cm.estimatedTokens, tokensBefore)
    }

    // MARK: - Fallback on provider error

    func test_compactWithSummaryIfNeeded_falls_back_to_static_sentinel_on_provider_error() async {
        let provider = MockProvider(shouldFail: true)
        let cm = makeContextAboveThreshold()

        // Must not throw; must still compact using the static sentinel.
        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertTrue(fired, "compaction must still fire even when the provider call fails")
        let hasSystemMessage = cm.messages.contains { $0.role == .system }
        XCTAssertTrue(hasSystemMessage, "a fallback system message must be inserted on provider error")
    }

    // MARK: - Idempotency

    func test_compactWithSummaryIfNeeded_does_not_fire_again_after_compaction() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)
        let countAfterFirst = cm.compactionCount

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(cm.compactionCount, countAfterFirst,
                       "must not compact again when tokens are already below threshold")
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

Expected: **BUILD FAILED** — `ContextManager` has no `compactWithSummaryIfNeeded(provider:)` method and `compact(force:customDigest:)` overload does not exist.

## Commit

```bash
git add MerlinTests/Unit/LLMSummarisationCompactionTests.swift
git commit -m "Phase 206a — LLMSummarisationCompactionTests (failing)"
```
