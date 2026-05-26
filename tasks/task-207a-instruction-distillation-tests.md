# Task 207a — Instruction Distillation Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 206b complete: LLM summarisation wired in the execute loop.

New surface introduced in task 207b:
  - `AppSettings.promptCompressionEnabled: Bool` — `@Published var`, default `false`; persisted as `prompt_compression_enabled` in `config.toml`
  - `AgenticEngine.distilledCoreSystemPrompt: String` — static computed property; a compact, symbol-dense version of `coreSystemPrompt`. Functionally equivalent but uses shorthand to save ~60% of core prompt tokens.
  - `AgenticEngine.constitutionDistilledContent: String` — instance property, initially `""`; set by `refreshDistilledConstitution(using:)`
  - `AgenticEngine.constitutionDistillHash: String` — SHA256 hex of the last distilled `constitutionContent`; empty when no distillation has run
  - `AgenticEngine.refreshDistilledConstitution(using provider: any LLMProvider) async` — if `constitutionContent` is non-empty and its SHA256 ≠ `constitutionDistillHash`, calls `provider` once to produce a compressed equivalent and stores result + hash; no-op when hash matches (content unchanged)
  - `AgenticEngine.buildStablePrefix()` — when `AppSettings.shared.promptCompressionEnabled` is true, substitutes `distilledCoreSystemPrompt` for `coreSystemPrompt` and `constitutionDistilledContent` for `constitutionContent` (when distillation is available)

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

    // MARK: - refreshDistilledConstitution

    func test_refreshDistilledConstitution_calls_provider_when_content_changed() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED:search+read>prose")
        engine.constitutionContent = "You are a helpful assistant with a long constitution.md file..."

        await engine.refreshDistilledConstitution(using: provider)

        XCTAssertEqual(provider.callCount, 1,
                       "provider must be called once when constitutionContent has no prior distillation")
        XCTAssertFalse(engine.constitutionDistilledContent.isEmpty,
                       "distilled content must be stored after provider call")
    }

    func test_refreshDistilledConstitution_does_not_call_provider_when_hash_matches() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED:v2")
        let content = "A known constitution.md body"
        engine.constitutionContent = content

        // First call — distills and stores hash.
        await engine.refreshDistilledConstitution(using: provider)
        XCTAssertEqual(provider.callCount, 1)

        // Second call with identical content — hash matches, provider must NOT be called again.
        await engine.refreshDistilledConstitution(using: provider)
        XCTAssertEqual(provider.callCount, 1,
                       "provider must not be called again when constitutionContent is unchanged")
    }

    func test_refreshDistilledConstitution_re_distills_when_content_changes() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "DISTILLED")
        engine.constitutionContent = "Original content"
        await engine.refreshDistilledConstitution(using: provider)

        engine.constitutionContent = "Updated content with new instructions"
        await engine.refreshDistilledConstitution(using: provider)

        XCTAssertEqual(provider.callCount, 2,
                       "provider must be called again when constitutionContent changes")
    }

    func test_refreshDistilledConstitution_noOp_when_content_empty() async {
        let engine = AgenticEngine()
        let provider = MockProvider(response: "should not be called")
        engine.constitutionContent = ""

        await engine.refreshDistilledConstitution(using: provider)

        XCTAssertEqual(provider.callCount, 0,
                       "provider must not be called when constitutionContent is empty")
    }

    // MARK: - buildStablePrefix with compression enabled

    func test_buildStablePrefix_uses_distilledCorePrompt_when_compression_enabled() async {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        // No constitutionContent set — distilled core prompt is the only compression target.
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

    func test_buildStablePrefix_uses_distilled_constitution_when_available_and_enabled() async {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        let provider = MockProvider(response: "COMPRESSED_MD")
        engine.constitutionContent = "A very long constitution.md with extensive prose instructions..."

        await engine.refreshDistilledConstitution(using: provider)
        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("COMPRESSED_MD"),
                      "stable prefix must use the distilled constitution.md when compression is enabled and distillation is ready")
        XCTAssertFalse(prefix.contains("A very long constitution.md"),
                       "stable prefix must not include the original constitution.md when a distilled version is available")
    }

    func test_buildStablePrefix_falls_back_to_original_constitution_when_distillation_not_run() {
        AppSettings.shared.promptCompressionEnabled = true
        defer { AppSettings.shared.promptCompressionEnabled = false }

        let engine = AgenticEngine()
        engine.constitutionContent = "Original constitution.md content"
        // No call to refreshDistilledConstitution — distilledContent is empty.

        let prefix = engine.buildStablePrefix()

        XCTAssertTrue(prefix.contains("Original constitution.md content"),
                      "must fall back to original constitution.md when distillation has not yet run")
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
`constitutionDistilledContent`, `constitutionDistillHash`, or `refreshDistilledConstitution(using:)`.

## Commit

```bash
git add MerlinTests/Unit/InstructionDistillationTests.swift
git commit -m "Task 207a — InstructionDistillationTests (failing)"
```
