import XCTest
@testable import Merlin

@MainActor
final class ProviderModelPickerTests: XCTestCase {

    private func makeRegistry() -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        return ProviderRegistry(persistURL: tmp)
    }

    // MARK: knownModels content

    func testDeepSeekHasKnownModels() {
        let models = ProviderRegistry.knownModels["deepseek"]
        XCTAssertNotNil(models)
        XCTAssertTrue(models!.contains("deepseek-chat"))
        XCTAssertTrue(models!.contains("deepseek-reasoner"))
    }

    func testOpenAIHasKnownModels() {
        let models = ProviderRegistry.knownModels["openai"]
        XCTAssertNotNil(models)
        XCTAssertFalse(models!.isEmpty)
        XCTAssertTrue(models!.contains("gpt-4o"))
    }

    func testAnthropicHasKnownModels() {
        let models = ProviderRegistry.knownModels["anthropic"]
        XCTAssertNotNil(models)
        XCTAssertFalse(models!.isEmpty)
        XCTAssertTrue(models!.contains("claude-sonnet-4-6"))
    }

    func testQwenHasKnownModels() {
        let models = ProviderRegistry.knownModels["qwen"]
        XCTAssertNotNil(models)
        XCTAssertFalse(models!.isEmpty)
    }

    // Local providers have no fixed model list — user types whatever is loaded
    func testOllamaHasNoKnownModels() {
        XCTAssertNil(ProviderRegistry.knownModels["ollama"])
    }

    func testLMStudioHasNoKnownModels() {
        XCTAssertNil(ProviderRegistry.knownModels["lmstudio"])
    }

    // MARK: updateModel persistence

    func testUpdateModelChangesConfigModel() {
        let registry = makeRegistry()
        registry.updateModel("deepseek-reasoner", for: "deepseek")
        let model = registry.providers.first { $0.id == "deepseek" }?.model
        XCTAssertEqual(model, "deepseek-reasoner")
    }

    func testUpdateModelPersistsAcrossRegistryReload() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        let registry = ProviderRegistry(persistURL: tmp)
        registry.updateModel("deepseek-reasoner", for: "deepseek")

        let reloaded = ProviderRegistry(persistURL: tmp)
        let model = reloaded.providers.first { $0.id == "deepseek" }?.model
        XCTAssertEqual(model, "deepseek-reasoner")
    }

    func testUpdateModelForUnknownIDDoesNothing() {
        let registry = makeRegistry()
        let countBefore = registry.providers.count
        registry.updateModel("some-model", for: "nonexistent-provider")
        XCTAssertEqual(registry.providers.count, countBefore)
    }
}
