# Task 192a — KAGEngine AgenticEngine Wiring Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

Task 191b complete: KAGEngine, XcalibreKAGPlugin, LocalKAGPlugin, AppSettings KAG fields,
and RAGTools enrichment are all implemented. However, `KAGEngine.shared.scheduleExtraction`
is never called from `AgenticEngine` — extraction is built but never triggered.

New surface introduced in task 192b:
  - `KAGEngine.pendingTask` — changed from `private` to `private(set)` to allow test
    observation via `@testable import Merlin`
  - `AgenticEngine.kagEngine: KAGEngine` — injectable property (defaults to
    `KAGEngine.shared`) so tests can provide a fresh engine per test

TDD coverage:
  File 1 — AgenticEngineKAGWiringTests: asserts that after a completed assistant turn
  with `kagEnabled=true` and a non-empty response, `engine.pendingTask` is non-nil.
  Also asserts that when `kagEnabled=false`, `pendingTask` remains nil.

---

## Write to: MerlinTests/Unit/AgenticEngineKAGWiringTests.swift

```swift
//  AgenticEngineKAGWiringTests.swift
//  Verifies that AgenticEngine calls KAGEngine.scheduleExtraction after each
//  assistant turn when kagEnabled = true, and skips it when kagEnabled = false.
//
//  scheduleExtraction() sets self.pendingTask synchronously (before the 2-second
//  idle delay), so we can assert it is non-nil immediately after the turn.

import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineKAGWiringTests: XCTestCase {

    private var settingsURL: URL!

    override func setUp() async throws {
        settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kag-wiring-\(UUID().uuidString).toml")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: settingsURL)
        // Reset kagEnabled to default so other tests are not polluted.
        AppSettings.shared.kagEnabled = false
    }

    // MARK: - Enabled

    func test_scheduleExtraction_called_when_kagEnabled() async throws {
        AppSettings.shared.kagEnabled = true

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "Swift is a compiled language."), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "Tell me about Swift.") {}

        XCTAssertNotNil(kag.pendingTask,
            "pendingTask must be non-nil — scheduleExtraction() was not called")

        kag.pendingTask?.cancel()
    }

    // MARK: - Disabled

    func test_scheduleExtraction_skipped_when_kagDisabled() async throws {
        AppSettings.shared.kagEnabled = false

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "hello"), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "hi") {}

        XCTAssertNil(kag.pendingTask,
            "pendingTask must be nil — scheduleExtraction() must not fire when kagEnabled=false")
    }

    // MARK: - Empty response

    func test_scheduleExtraction_skipped_for_empty_response() async throws {
        AppSettings.shared.kagEnabled = true

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "hi") {}

        XCTAssertNil(kag.pendingTask,
            "pendingTask must be nil — scheduleExtraction() must not fire for empty response text")
    }
}
```

> **Note:** `makeEngine(provider:kagEngine:)` is a new overload of the existing
> `makeEngine(provider:)` helper in `TestHelpers/EngineFactory.swift`.
> Add it there rather than in the test file.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — `AgenticEngineKAGWiringTests` references
`kag.pendingTask` (currently `private`) and `makeEngine(provider:kagEngine:)`
(does not yet exist).

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineKAGWiringTests.swift
git commit -m "Task 192a — AgenticEngineKAGWiringTests (failing)"
```
