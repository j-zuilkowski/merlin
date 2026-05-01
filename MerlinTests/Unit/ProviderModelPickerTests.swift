import XCTest
@testable import Merlin

@MainActor
final class ProviderModelPickerTests: XCTestCase {

    private func makeRegistry() -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        return ProviderRegistry(persistURL: tmp)
    }

    // MARK: Dynamic model cache

    func testModelsCacheStartsEmpty() {
        let registry = makeRegistry()
        XCTAssertTrue(registry.modelsByProviderID.isEmpty)
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
