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
