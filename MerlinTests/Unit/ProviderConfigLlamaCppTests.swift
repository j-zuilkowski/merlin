import XCTest
@testable import Merlin

@MainActor
final class ProviderConfigLlamaCppTests: XCTestCase {

    func testDefaultProvidersIncludeDisabledLlamaCppProvider() {
        guard let provider = ProviderRegistry.defaultProviders.first(where: { $0.id == "llamacpp" }) else {
            return XCTFail("Expected default llamacpp provider")
        }

        XCTAssertEqual(provider.displayName, "llama.cpp")
        XCTAssertEqual(provider.baseURL, "http://localhost:8081/v1")
        XCTAssertTrue(provider.model.isEmpty)
        XCTAssertFalse(provider.isEnabled)
        XCTAssertEqual(provider.kind, .openAICompatible)
        XCTAssertTrue(provider.supportsVision)
        XCTAssertEqual(provider.localModelManagerID, "llamacpp")
    }

    func testDefaultProviderCountIncludesLlamaCpp() {
        XCTAssertEqual(ProviderRegistry.defaultProviders.count, 12)
    }

    func testLocalProviderCalibrationDefaultsIncludeLlamaCpp() {
        let localIDs = Set(ProviderRegistry.defaultProviders.filter(\.isLocal).map(\.id))
        XCTAssertTrue(localIDs.contains("llamacpp"))
    }

    func testSlotPickerCanExposeLlamaCppVirtualModelIDs() {
        let registry = makeRegistry()
        registry.setEnabled(true, for: "llamacpp")
        registry.modelsByProviderID["llamacpp"] = ["qwen3-coder", "qwen3-vl"]

        let ids = Set(registry.allSlotPickerEntries.map(\.id))
        XCTAssertTrue(ids.contains("llamacpp:qwen3-coder"))
        XCTAssertTrue(ids.contains("llamacpp:qwen3-vl"))
    }

    func testVirtualLlamaCppProviderPreservesSelectedModelID() throws {
        let registry = makeRegistry()
        registry.setEnabled(true, for: "llamacpp")
        registry.modelsByProviderID["llamacpp"] = ["qwen3-coder"]

        let provider = try XCTUnwrap(registry.provider(for: "llamacpp:qwen3-coder"))
        XCTAssertEqual(provider.id, "llamacpp:qwen3-coder")
        XCTAssertEqual(provider.baseURL, URL(string: "http://localhost:8081/v1"))

        let openAIProvider = try XCTUnwrap(provider as? OpenAICompatibleProvider)
        let request = CompletionRequest(model: "", messages: [], tools: nil)
        let urlRequest = try openAIProvider.buildRequest(request)
        let body = try XCTUnwrap(urlRequest.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen3-coder")
    }

    private func makeRegistry() -> ProviderRegistry {
        ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-llamacpp-provider-\(UUID().uuidString).json"),
            initialProviders: ProviderRegistry.defaultProviders
        )
    }
}
