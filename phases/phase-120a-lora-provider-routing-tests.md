# Phase 120a — LoRA Provider Routing Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 119b complete: LoRACoordinator auto-train trigger in place.

Current state: AgenticEngine.provider(for: .execute) always returns proProvider.
When a trained adapter is available and loraAutoLoad=true, the execute slot should route
through a local mlx_lm.server instead — an OpenAI-compatible endpoint at loraServerURL.
The critic (.reason slot) always uses the unmodified base model to keep evaluation unbiased.

New surface introduced in phase 120b:
  - `AgenticEngine.loraProvider: (any LLMProvider)?` — set by AppState via Combine when
    loraEnabled + loraAutoLoad + loraAdapterPath file exists + loraServerURL non-empty;
    cleared when any condition fails.
  - `AgenticEngine.provider(for:)` returns `loraProvider` instead of `proProvider` when
    loraProvider is non-nil AND slot == .execute.
  - AppState wires loraProvider via `AppSettings.$loraAutoLoad` Combine observation.

TDD coverage:
  File 1 — LoRAProviderRoutingTests: execute slot returns loraProvider when set; execute
            slot falls back to proProvider when loraProvider nil; reason slot always returns
            flashProvider regardless of loraProvider; setting loraProvider to nil restores
            proProvider for execute.

---

## Write to: MerlinTests/Unit/LoRAProviderRoutingTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class LoRAProviderRoutingTests: XCTestCase {

    // MARK: - Execute slot returns loraProvider when set

    func testExecuteSlotReturnsLoRAProviderWhenSet() {
        let engine = makeEngine()
        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"

        // BUILD FAILED until 120b adds AgenticEngine.loraProvider
        engine.loraProvider = loraProvider

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "lora-local",
                      "Execute slot must return loraProvider when it is set")
    }

    // MARK: - Falls back to proProvider when loraProvider is nil

    func testExecuteSlotFallsBackToProProviderWhenLoRANil() {
        let proMock = MockProvider()
        proMock.id_ = "pro"
        let engine = makeEngine(proProvider: proMock)
        engine.loraProvider = nil

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "pro",
                      "Execute slot must fall back to proProvider when loraProvider is nil")
    }

    // MARK: - Reason slot always unaffected by loraProvider

    func testReasonSlotAlwaysUsesFlashProvider() {
        let flashMock = MockProvider()
        flashMock.id_ = "flash"
        let engine = makeEngine(flashProvider: flashMock)

        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"
        engine.loraProvider = loraProvider

        let resolved = engine.provider(for: .reason)
        XCTAssertTrue((resolved as? MockProvider)?.id == "flash",
                      "Reason slot must always use flashProvider, never loraProvider")
    }

    // MARK: - Clearing loraProvider restores proProvider

    func testClearingLoRAProviderRestoresProProvider() {
        let proMock = MockProvider()
        proMock.id_ = "pro"
        let engine = makeEngine(proProvider: proMock)

        let loraProvider = MockProvider()
        loraProvider.id_ = "lora-local"
        engine.loraProvider = loraProvider

        // Clear it
        engine.loraProvider = nil

        let resolved = engine.provider(for: .execute)
        XCTAssertTrue((resolved as? MockProvider)?.id == "pro",
                      "Clearing loraProvider must restore proProvider for execute slot")
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AgenticEngine.loraProvider` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRAProviderRoutingTests.swift
git commit -m "Phase 120a — LoRAProviderRoutingTests (failing)"
```
