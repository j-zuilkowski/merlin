// StablePrefixCacheTests.swift
// Phase 197a — failing tests for stable system-prompt prefix caching.
import XCTest
@testable import Merlin

@MainActor
final class StablePrefixCacheTests: XCTestCase {

    private func makeEngine() -> AgenticEngine {
        AgenticEngine()
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            AppSettings.shared.cagEnabled = false
            AppSettings.shared.cagPinClaudeMD = true
            AppSettings.shared.cagPinnedPhaseDocs = []
        }
        super.tearDown()
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

    func test_cagPinnedPhaseDocs_areIncludedInStablePrefix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cag-prefix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "Pinned task content".write(
            to: dir.appendingPathComponent("phase.md"),
            atomically: true,
            encoding: .utf8)

        let engine = makeEngine()
        engine.currentProjectPath = dir.path
        AppSettings.shared.cagEnabled = true
        AppSettings.shared.cagPinnedPhaseDocs = ["phase.md"]

        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("Pinned CAG document: phase.md"))
        XCTAssertTrue(prefix.contains("Pinned task content"))
    }

    func test_cagPinnedPhaseDocs_skipTraversalOutsideCurrentProject() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cag-prefix-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("cag-outside-\(UUID().uuidString).md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "Secret outside content".write(to: outside, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outside)
        }

        let engine = makeEngine()
        engine.currentProjectPath = dir.path
        AppSettings.shared.cagEnabled = true
        AppSettings.shared.cagPinnedPhaseDocs = [outside.path]

        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("outside current project"))
        XCTAssertFalse(prefix.contains("Secret outside content"))
    }

    func test_cagPinnedPhaseDocs_skipOversizedFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cag-prefix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let oversized = dir.appendingPathComponent("large.md")
        try String(repeating: "x", count: 70 * 1024).write(
            to: oversized,
            atomically: true,
            encoding: .utf8)

        let engine = makeEngine()
        engine.currentProjectPath = dir.path
        AppSettings.shared.cagEnabled = true
        AppSettings.shared.cagPinnedPhaseDocs = ["large.md"]

        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("file exceeds 64 KiB limit"))
        XCTAssertFalse(prefix.contains(String(repeating: "x", count: 256)))
    }

    func test_cagPinClaudeMDFalse_excludesClaudeFromStablePrefix() {
        let engine = makeEngine()
        engine.claudeMDContent = "CLAUDE SHOULD NOT BE PINNED"
        AppSettings.shared.cagEnabled = true
        AppSettings.shared.cagPinClaudeMD = false

        let prefix = engine.buildStablePrefix()

        XCTAssertFalse(prefix.contains("CLAUDE SHOULD NOT BE PINNED"))
    }

    func test_cagPinClaudeMDFalse_keepsClaudeInHotSystemSuffix() {
        let engine = makeEngine()
        engine.claudeMDContent = "CLAUDE SHOULD REMAIN HOT"
        AppSettings.shared.cagEnabled = true
        AppSettings.shared.cagPinClaudeMD = false

        let segments = engine.buildCAGSystemPromptSegments()

        XCTAssertFalse(segments.cacheable.contains("CLAUDE SHOULD REMAIN HOT"))
        XCTAssertTrue(segments.hot.contains("CLAUDE SHOULD REMAIN HOT"))
        XCTAssertTrue(segments.merged.contains("CLAUDE SHOULD REMAIN HOT"))
    }
}
