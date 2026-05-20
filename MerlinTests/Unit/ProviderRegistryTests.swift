import XCTest
@testable import Merlin

@MainActor
final class ProviderRegistryTests: XCTestCase {

    // Use a temp path so tests never touch ~/Library
    private func makeRegistry() -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        return ProviderRegistry(persistURL: tmp)
    }

    // MARK: Defaults

    func testDefaultProvidersCount() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.providers.count, 11)
    }

    func testDefaultActiveProvider() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.activeProviderID, "deepseek")
    }

    func testDeepSeekSupportsThinking() {
        let registry = makeRegistry()
        let ds = registry.providers.first { $0.id == "deepseek" }
        XCTAssertNotNil(ds)
        XCTAssertTrue(ds!.supportsThinking)
    }

    func testAnthropicSupportsThinking() {
        let registry = makeRegistry()
        let a = registry.providers.first { $0.id == "anthropic" }
        XCTAssertNotNil(a)
        XCTAssertTrue(a!.supportsThinking)
    }

    func testOllamaIsLocal() {
        let registry = makeRegistry()
        let o = registry.providers.first { $0.id == "ollama" }
        XCTAssertNotNil(o)
        XCTAssertTrue(o!.isLocal)
    }

    func testLMStudioSupportsVision() {
        let registry = makeRegistry()
        let lm = registry.providers.first { $0.id == "lmstudio" }
        XCTAssertNotNil(lm)
        XCTAssertTrue(lm!.supportsVision)
    }

    func testOpenAISupportsVision() {
        let registry = makeRegistry()
        let oa = registry.providers.first { $0.id == "openai" }
        XCTAssertNotNil(oa)
        XCTAssertTrue(oa!.supportsVision)
    }

    // MARK: Mutation

    func testToggleEnabled() {
        let registry = makeRegistry()
        let id = "openai"
        let original = registry.providers.first { $0.id == id }!.isEnabled
        registry.setEnabled(!original, for: id)
        let updated = registry.providers.first { $0.id == id }!.isEnabled
        XCTAssertNotEqual(original, updated)
    }

    // MARK: Factory

    func testMakeLLMProviderOpenAICompat() {
        let registry = makeRegistry()
        let config = registry.providers.first { $0.id == "deepseek" }!
        let provider = registry.makeLLMProvider(for: config)
        XCTAssertEqual(provider.id, "deepseek")
    }

    func testMakeLLMProviderAnthropic() {
        let registry = makeRegistry()
        let config = registry.providers.first { $0.id == "anthropic" }!
        let provider = registry.makeLLMProvider(for: config)
        XCTAssertEqual(provider.id, "anthropic")
    }

    func testActiveConfigReflectsActiveProviderID() {
        let registry = makeRegistry()
        registry.activeProviderID = "anthropic"
        // Anthropic is disabled by default — enable it first
        registry.setEnabled(true, for: "anthropic")
        XCTAssertEqual(registry.activeConfig?.id, "anthropic")
    }

    // MARK: Provider routing — primaryProvider

    func testPrimaryProviderIDMatchesActiveProviderID() {
        let registry = makeRegistry()
        // DeepSeek is active and enabled by default
        let primary = registry.primaryProvider
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.id, "deepseek")
    }

    func testPrimaryProviderNilWhenActiveProviderIsDisabled() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "deepseek")
        // No other provider is active
        XCTAssertNil(registry.primaryProvider)
    }

    // MARK: Learned context window persistence

    private func tempPersistURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
    }

    func testRecordLearnedContextWindowPersistsAValidObservation() {
        let tmp = tempPersistURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Seed providers.json on disk (lmstudio default carries no budget).
        ProviderRegistry(persistURL: tmp).setEnabled(true, for: "lmstudio")

        ProviderRegistry.recordLearnedContextWindow(32_768, for: "lmstudio", persistURL: tmp)

        let budget = ProviderRegistry.persistedBudget(for: "lmstudio", persistURL: tmp)
        XCTAssertEqual(budget?.maxInputTokens, 32_768)
        XCTAssertGreaterThan(budget?.usableInputTokens ?? 0, 0)
    }

    func testRecordLearnedContextWindowRejectsAZeroObservation() {
        let tmp = tempPersistURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Seed a healthy persisted budget for lmstudio.
        let healthy = ProviderBudget(maxInputTokens: 32_768, reservedOutputTokens: 4_096)
        ProviderRegistry(persistURL: tmp).updateBudget(healthy, for: "lmstudio")

        // LM Studio reporting loaded_context_length 0 must not overwrite a healthy budget.
        ProviderRegistry.recordLearnedContextWindow(0, for: "lmstudio", persistURL: tmp)

        XCTAssertEqual(ProviderRegistry.persistedBudget(for: "lmstudio", persistURL: tmp), healthy,
                       "a zero observation must not corrupt the persisted budget")
    }

    func testRecordLearnedContextWindowRejectsAnObservationBelowReservedOutput() {
        let tmp = tempPersistURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // No prior budget — existingReserved defaults to 4096; an observation of 4096
        // leaves zero usable input and must be rejected, leaving the budget unset.
        ProviderRegistry(persistURL: tmp).setEnabled(true, for: "lmstudio")

        ProviderRegistry.recordLearnedContextWindow(4_096, for: "lmstudio", persistURL: tmp)

        XCTAssertNil(ProviderRegistry.persistedBudget(for: "lmstudio", persistURL: tmp),
                     "an observation that yields zero usable input must not be persisted")
    }

}
