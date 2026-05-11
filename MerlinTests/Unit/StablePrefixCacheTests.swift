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
        engine.claudeMDContent = "# Instructions\nDo stuff."
        let first = engine.buildStablePrefix()
        let second = engine.buildStablePrefix()
        XCTAssertEqual(first, second)
    }

    // MARK: - Cache invalidation

    /// Changing claudeMDContent must cause the next buildStablePrefix() call to
    /// return a different string.
    /// FAILS before 197b — _stablePrefixDirty / buildStablePrefix() do not exist.
    func test_stablePrefix_changesWhenClaudeMDContentChanges() {
        let engine = makeEngine()
        engine.claudeMDContent = "v1"
        let first = engine.buildStablePrefix()
        engine.claudeMDContent = "v2"
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
