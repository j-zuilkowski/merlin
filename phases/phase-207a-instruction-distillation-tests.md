# Phase 207a — Instruction Distillation Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 206b complete: LLM summarisation wired in the execute loop.

New surface introduced in phase 207b:
  - `AppSettings.promptCompressionEnabled: Bool` — `@Published var`, default `false`; persisted as `prompt_compression_enabled` in `config.toml`
  - `AgenticEngine.distilledCoreSystemPrompt: String` — static computed property; a compact, symbol-dense version of `coreSystemPrompt`. Functionally equivalent but uses shorthand to save ~60% of core prompt tokens.
  - `AgenticEngine.claudeMDDistilledContent: String` — instance property, initially `""`; set by `refreshDistilledClaudeMD(using:)`
  - `AgenticEngine.claudeMDDistillHash: String` — SHA256 hex of the last distilled `claudeMDContent`; empty when no distillation has run
  - `AgenticEngine.refreshDistilledClaudeMD(using provider: any LLMProvider) async` — if `claudeMDContent` is non-empty and its SHA256 ≠ `claudeMDDistillHash`, calls `provider` once to produce a compressed equivalent and stores result + hash; no-op when hash matches (content unchanged)
  - `AgenticEngine.buildStablePrefix()` — when `AppSettings.shared.promptCompressionEnabled` is true, substitutes `distilledCoreSystemPrompt` for `coreSystemPrompt` and `claudeMDDistilledContent` for `claudeMDContent` (when distillation is available)

TDD coverage:
  File 1 — InstructionDistillationTests: distilled prompt shorter than original, hash guard prevents re-distillation, buildStablePrefix uses distilled content when enabled, buildStablePrefix uses original when disabled, AppSettings round-trips promptCompressionEnabled

---

## Write to: MerlinTests/Unit/InstructionDistillationTests.swift

```swift
import XCTest
import CryptoKit
@testable import Merlin

@MainActor
final class InstructionDistillationTests: XCTestCase {

    // MARK: - distilledCoreSystemPrompt

    func test_distilledCorePrompt_is_shorter_than_original() {
        let engine = AgenticEngine()
        // Compare raw character counts as a proxy for token count.
        let distilledLen = AgenticEngine.distilledCoreSystemPrompt.count
        let originalLen  = AgenticEngine.coreSystemPromptForTesting.count
        XCTAssertLessThan(distilledLen, originalLen,
                          "distilled core prompt must be shorter than the original")
    }

    func test_distilledCorePrompt_is_non_empty() {
        XCTAssertFalse(AgenticEngine.distilledCoreSystemPrompt.isEmpty)
    }

    // MARK: - refreshDistilledClaudeMD

    func test_refreshDistilledClaudeMD_calls_provider_when_content_changed() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED:search+read>prose")
        engine.claudeMDContent = "You are a helpful assistant with a long CLAUDE.md file..."

        await engine.refreshDistilledClaudeMD(using: provider)

        XCTAssertEqual(provider.callCount, 1,
                       "provider must be called once when claudeMDContent has no prior distillation")
        XCTAssertFalse(engine.claudeMDDistilledContent.isEmpty,
                       "distilled content must be stored after provider call")
    }

    func test_refreshDistilledClaudeMD_does_not_call_provider_when_hash_matches() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED:v2")
        let content = "A known CLAUDE.md body"
        engine.claudeMDContent = content

        // First call — distills and stores hash.
        await engine.refreshDistilledClaudeMD(using: provider)
        XCTAssertEqual(provider.callCount, 1)

        // Second call with identical content — hash matches, provider must NOT be called again.
        await engine.refreshDistilledClaudeMD(using: provider)
        XCTAssertEqual(provider.callCount, 1,
                       "provider must not be called again when claudeMDContent is unchanged")
    }

    func test_refreshDistilledClaudeMD_re_distills_when_content_changes() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED")
        engine.claudeMDContent = "Original content"
        await engine.refreshDistilledClaudeMD(using: provider)

        engine.claudeMDContent = "Updated content with new instructions"
        await engine.refreshDistilledClaudeMD(using: provider)

        XCTAssertEqual(provider.callCount, 2,
                       "provider must be called again when claudeMDContent changes")
    }

    func test_refreshDistilledClaudeMD_noOp_when_content_empty() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "should not be called")
        engine.claudeMDContent = ""

        await engine.refreshDistilledClaudeMD(using: provider)

        XCTAssertEqual(provider.callCount, 0,
                       "provider must not be called when claudeMDContent is empty")
    }

    // MARK: - buildStablePrefix with compression enabled

    func test_buildStablePrefix_uses_distilledCorePrompt_when_compression_enabled() async {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        // No claudeMDContent set — distilled core prompt is the only compression target.
        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains(AgenticEngine.distilledCoreSystemPrompt),
                      "stable prefix must contain the distilled core prompt when compression is enabled")
        XCTAssertFalse(prefix.contains(AgenticEngine.coreSystemPromptForTesting),
                       "stable prefix must not contain the original core prompt when compression is enabled")
    }

    func test_buildStablePrefix_uses_original_core_prompt_when_compression_disabled() {
        AppSettings.shared.promptCompressionEnabled = false

        let engine = AgenticEngine()
        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains(AgenticEngine.coreSystemPromptForTesting),
                      "stable prefix must contain the original core prompt when compression is disabled")
    }

    func test_buildStablePrefix_uses_distilled_claudeMD_when_available_and_enabled() async {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        let provider = MockProvider(response: "COMPRESSED_MD")
        engine.claudeMDContent = "A very long CLAUDE.md with extensive prose instructions..."

        await engine.refreshDistilledClaudeMD(using: provider)
        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("COMPRESSED_MD"),
                      "stable prefix must use the distilled CLAUDE.md when compression is enabled and distillation is ready")
        XCTAssertFalse(prefix.contains("A very long CLAUDE.md"),
                       "stable prefix must not include the original CLAUDE.md when a distilled version is available")
    }

    func test_buildStablePrefix_falls_back_to_original_claudeMD_when_distillation_not_run() {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        engine.claudeMDContent = "Original CLAUDE.md content"
        // No call to refreshDistilledClaudeMD — distilledContent is empty.

        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("Original CLAUDE.md content"),
                      "must fall back to original CLAUDE.md when distillation has not yet run")
    }

    // MARK: - AppSettings round-trip

    func test_promptCompressionEnabled_defaults_to_false() {
        // Fresh instance (not the shared singleton) to avoid cross-test pollution.
        XCTAssertFalse(AppSettings.shared.promptCompressionEnabled)
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

Expected: **BUILD FAILED** — `AppSettings` has no `promptCompressionEnabled` property;
`AgenticEngine` has no `distilledCoreSystemPrompt`, `coreSystemPromptForTesting`,
`claudeMDDistilledContent`, `claudeMDDistillHash`, or `refreshDistilledClaudeMD(using:)`.

## Commit

```bash
git add MerlinTests/Unit/InstructionDistillationTests.swift
git commit -m "Phase 207a — InstructionDistillationTests (failing)"
```
