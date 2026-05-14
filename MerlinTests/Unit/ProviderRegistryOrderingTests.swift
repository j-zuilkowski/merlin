import XCTest
@testable import Merlin

@MainActor
final class ProviderRegistryOrderingTests: XCTestCase {

    private func makeProvider(
        id: String,
        maxInputTokens: Int,
        reservedOutputTokens: Int,
        isEnabled: Bool = true
    ) -> ProviderConfig {
        ProviderConfig(
            id: id,
            displayName: id.uppercased(),
            baseURL: "http://localhost",
            model: id,
            isEnabled: isEnabled,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible,
            budget: ProviderBudget(
                maxInputTokens: maxInputTokens,
                reservedOutputTokens: reservedOutputTokens
            )
        )
    }

    private func makeRegistry(_ providers: [ProviderConfig]) -> ProviderRegistry {
        ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-provider-order-\(UUID().uuidString).json"),
            initialProviders: providers
        )
    }

    func testProvidersAreSortedByDescendingUsableInputTokens() {
        let registry = makeRegistry([
            makeProvider(id: "tiny", maxInputTokens: 12_000, reservedOutputTokens: 4_000),
            makeProvider(id: "medium", maxInputTokens: 48_000, reservedOutputTokens: 8_000),
            makeProvider(id: "large", maxInputTokens: 96_000, reservedOutputTokens: 8_000)
        ])

        let ordered = registry.providersOrderedByBudget()
        XCTAssertEqual(ordered.map { $0.id }, ["large", "medium", "tiny"])
    }

    func testProviderOrderingBreaksTiesByID() {
        let registry = makeRegistry([
            makeProvider(id: "zeta", maxInputTokens: 32_000, reservedOutputTokens: 4_096),
            makeProvider(id: "alpha", maxInputTokens: 32_000, reservedOutputTokens: 4_096)
        ])

        let ordered = registry.providersOrderedByBudget()
        XCTAssertEqual(ordered.map { $0.id }, ["alpha", "zeta"])
    }

    func testUnconfiguredProvidersAreExcluded() {
        let registry = makeRegistry([
            makeProvider(id: "enabled", maxInputTokens: 64_000, reservedOutputTokens: 4_096),
            makeProvider(id: "disabled", maxInputTokens: 128_000, reservedOutputTokens: 4_096, isEnabled: false)
        ])

        let ordered = registry.providersOrderedByBudget()
        XCTAssertEqual(ordered.map { $0.id }, ["enabled"])
    }
}
