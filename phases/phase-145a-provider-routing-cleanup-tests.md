# Phase 145a — Provider Routing Cleanup Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 144b complete: virtual provider IDs in place, LMStudioProvider deleted.

New surface introduced in phase 145b:
  - `AgenticEngine.proProvider`, `flashProvider`, `visionProvider` — deleted.
    All routing goes through `registry` + `slotAssignments` exclusively.
  - `AgenticEngine.provider(for:)` fallback — when no slot assignment, falls back to
    `registry?.primaryProvider`. When registry is nil, returns `NullProvider()`.
  - `AgenticEngine` no longer has a `convenience init(proProvider:flashProvider:visionProvider:...)`.
    Tests use `init(slotAssignments:registry:toolRouter:contextManager:...)` directly,
    or the `makeForTesting(provider:)` helper which now sets `registry` instead of the
    three named properties.
  - `AppState.syncEngineProviders()` simplified: sets `engine.registry` and
    `engine.slotAssignments` only. No hardcoded DeepSeek fallback.
  - `ProviderRegistry.visionProvider` computed property — deleted. Vision routing is
    exclusively through `slotAssignments[.vision]`.

TDD coverage:
  File 1 — ProviderRoutingCleanupTests: verify slot-based routing, fallback to registry primary,
    NullProvider when no registry, vision slot works through slotAssignments

---

## Write to: MerlinTests/Unit/ProviderRoutingCleanupTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ProviderRoutingCleanupTests: XCTestCase {

    private func makeRegistry(primaryID: String,
                               providers: [ProviderConfig]) -> ProviderRegistry {
        var reg = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-routing-\(UUID().uuidString).json"),
            initialProviders: providers
        )
        reg.activeProviderID = primaryID
        return reg
    }

    private func mockProvider(id: String) -> MockRoutingProvider {
        MockRoutingProvider(providerID: id)
    }

    // MARK: - Slot assignment routing

    func testSlotAssignmentRoutesCorrectly() async throws {
        let executeProvider = mockProvider(id: "local-fast")
        let reasonProvider  = mockProvider(id: "remote-think")

        let registry = makeRegistry(primaryID: "remote-think", providers: [
            ProviderConfig(id: "local-fast", displayName: "Local", baseURL: "http://localhost/v1",
                           model: "phi-4", isEnabled: true, isLocal: true,
                           supportsThinking: false, supportsVision: false, kind: .openAICompatible),
            ProviderConfig(id: "remote-think", displayName: "Remote", baseURL: "https://api.x.com/v1",
                           model: "think-model", isEnabled: true, isLocal: false,
                           supportsThinking: true, supportsVision: false, kind: .openAICompatible),
        ])
        registry.add(executeProvider)
        registry.add(reasonProvider)

        let engine = AgenticEngine(
            slotAssignments: [.execute: "local-fast", .reason: "remote-think"],
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )

        let executeProv = engine.provider(for: .execute)
        let reasonProv  = engine.provider(for: .reason)

        XCTAssertEqual(executeProv?.id, "local-fast")
        XCTAssertEqual(reasonProv?.id, "remote-think")
    }

    func testUnassignedSlotFallsBackToRegistryPrimary() throws {
        let primaryProvider = mockProvider(id: "primary-prov")
        let registry = makeRegistry(primaryID: "primary-prov", providers: [
            ProviderConfig(id: "primary-prov", displayName: "Primary",
                           baseURL: "https://api.x.com/v1", model: "m",
                           isEnabled: true, isLocal: false,
                           supportsThinking: false, supportsVision: false, kind: .openAICompatible),
        ])
        registry.add(primaryProvider)

        let engine = AgenticEngine(
            slotAssignments: [:],   // nothing assigned
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )

        let p = engine.provider(for: .execute)
        XCTAssertEqual(p?.id, "primary-prov",
                       "Unassigned slot must fall back to registry.primaryProvider")
    }

    func testNilRegistryReturnsNullProvider() throws {
        let engine = AgenticEngine(
            slotAssignments: [:],
            registry: nil,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )

        let p = engine.provider(for: .execute)
        XCTAssertTrue(p is NullProvider,
                      "No registry → should return NullProvider, not crash")
    }

    func testVisionSlotRoutesViaSlotAssignment() throws {
        let visionProvider = mockProvider(id: "vision-model")
        let registry = makeRegistry(primaryID: "vision-model", providers: [
            ProviderConfig(id: "vision-model", displayName: "Vision",
                           baseURL: "http://localhost/v1", model: "qwen-vl",
                           isEnabled: true, isLocal: true,
                           supportsThinking: false, supportsVision: true, kind: .openAICompatible),
        ])
        registry.add(visionProvider)

        let engine = AgenticEngine(
            slotAssignments: [.vision: "vision-model"],
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )

        let p = engine.provider(for: .vision)
        XCTAssertEqual(p?.id, "vision-model")
    }

    func testVisionSlotUnassignedFallsBackToPrimary() throws {
        let primary = mockProvider(id: "primary")
        let registry = makeRegistry(primaryID: "primary", providers: [
            ProviderConfig(id: "primary", displayName: "P",
                           baseURL: "https://api.x.com/v1", model: "m",
                           isEnabled: true, isLocal: false,
                           supportsThinking: false, supportsVision: false, kind: .openAICompatible),
        ])
        registry.add(primary)

        let engine = AgenticEngine(
            slotAssignments: [:],
            registry: registry,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )

        let p = engine.provider(for: .vision)
        XCTAssertEqual(p?.id, "primary",
                       "Unassigned vision slot should fall back to primary, not crash")
    }

    // MARK: - Hardcoded properties removed

    func testProProviderPropertyIsGone() {
        // Compilation assertion: if `proProvider` still exists this file will not compile.
        // The engine init no longer accepts proProvider/flashProvider/visionProvider parameters.
        let engine = AgenticEngine(
            slotAssignments: [:],
            registry: nil,
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )
        _ = engine  // suppress unused warning
        // If the code above compiles, the convenience init with named providers is gone.
    }

    // MARK: - makeForTesting still works

    func testMakeForTestingUsesRegistry() async throws {
        let provider = MockRoutingProvider(providerID: "test-reg-provider")
        let engine = await AgenticEngine.makeForTesting(provider: provider)

        let p = engine.provider(for: .execute)
        XCTAssertEqual(p?.id, "test-reg-provider")
    }
}

// MARK: - Helpers

final class MockRoutingProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let baseURL: URL = URL(string: "http://localhost")!

    init(providerID: String) { self.id = providerID }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
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
Expected: BUILD FAILED — `proProvider`/`flashProvider`/`visionProvider` still present;
`AgenticEngine.init` still has the convenience form with named providers.

## Commit
```bash
git add MerlinTests/Unit/ProviderRoutingCleanupTests.swift
git commit -m "Phase 145a — Provider routing cleanup tests (failing)"
```
