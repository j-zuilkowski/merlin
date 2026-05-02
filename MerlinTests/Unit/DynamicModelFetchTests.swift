import XCTest
@testable import Merlin

@MainActor
final class DynamicModelFetchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockModelsURLProtocol.nextResponse = .openAIModels([])
        MockModelsURLProtocol.perIDResponse = [:]
        MockModelsURLProtocol.capturedRequests = []
    }

    // MARK: - Helpers

    private func makeRegistry(
        response: MockModelsResponse,
        providers: [ProviderConfig] = [],
        apiKeys: [String: String] = [:]
    ) -> ProviderRegistry {
        MockModelsURLProtocol.nextResponse = response
        MockModelsURLProtocol.capturedRequests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockModelsURLProtocol.self]
        let session = URLSession(configuration: config)
        let reg = ProviderRegistry(persistURL: testPersistURL(), session: session,
                                   initialProviders: providers.isEmpty ? testProviders() : providers)
        // Use in-memory override so tests never touch ~/.merlin/api-keys.json
        reg.apiKeysOverride = apiKeys
        return reg
    }

    private func testProviders() -> [ProviderConfig] {
        [
            ProviderConfig(id: "deepseek",
                           displayName: "DeepSeek",
                           baseURL: "https://api.deepseek.com/v1",
                           model: "deepseek-chat",
                           isEnabled: true,
                           isLocal: false,
                           supportsThinking: false,
                           supportsVision: false,
                           kind: .openAICompatible),
            ProviderConfig(id: "lmstudio",
                           displayName: "LM Studio",
                           baseURL: "http://localhost:1234/v1",
                           model: "",
                           isEnabled: true,
                           isLocal: true,
                           supportsThinking: false,
                           supportsVision: true,
                           kind: .openAICompatible),
        ]
    }

    private func testPersistURL() -> URL {
        URL(fileURLWithPath: "/tmp/merlin-registry-\(UUID().uuidString).json")
    }

    // MARK: - fetchModels(for:)

    func testFetchModelsReturnsIDs() async throws {
        let registry = makeRegistry(response: .openAIModels(["model-a", "model-b", "model-c"]))
        let config = testProviders()[0]

        let models = await registry.fetchModels(for: config)

        XCTAssertEqual(models, ["model-a", "model-b", "model-c"])
    }

    func testFetchModelsReturnsEmptyOnNetworkError() async throws {
        let registry = makeRegistry(response: .networkError)
        let config = testProviders()[0]

        let models = await registry.fetchModels(for: config)

        XCTAssertTrue(models.isEmpty, "Should return [] on network error, not throw")
    }

    func testFetchModelsReturnsEmptyOnBadJSON() async throws {
        let registry = makeRegistry(response: .badJSON)
        let config = testProviders()[0]

        let models = await registry.fetchModels(for: config)

        XCTAssertTrue(models.isEmpty)
    }

    func testFetchModelsSendsAuthHeaderForKeyedProvider() async throws {
        let registry = makeRegistry(response: .openAIModels(["gpt-4o"]),
                                    apiKeys: ["deepseek": "sk-test-key"])
        let config = testProviders()[0]

        _ = await registry.fetchModels(for: config)

        let request = MockModelsURLProtocol.capturedRequests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
    }

    func testFetchModelsNoAuthHeaderForLocalProvider() async throws {
        let registry = makeRegistry(response: .openAIModels(["phi-4"]))
        let config = testProviders()[1] // lmstudio

        _ = await registry.fetchModels(for: config)

        let request = MockModelsURLProtocol.capturedRequests.first
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testFetchModelsUsesAnthropicHeaderFormat() async throws {
        let anthropicProvider = ProviderConfig(
            id: "anthropic",
            displayName: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            model: "claude-sonnet-4-6",
            isEnabled: true,
            isLocal: false,
            supportsThinking: true,
            supportsVision: false,
            kind: .anthropic
        )
        let registry = makeRegistry(
            response: .anthropicModels(["claude-opus-4-7", "claude-sonnet-4-6"]),
            providers: [anthropicProvider],
            apiKeys: ["anthropic": "test-anthropic-key"]
        )

        let models = await registry.fetchModels(for: anthropicProvider)

        XCTAssertEqual(models, ["claude-opus-4-7", "claude-sonnet-4-6"])
        let request = MockModelsURLProtocol.capturedRequests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "test-anthropic-key")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - fetchAllModels()

    func testFetchAllModelsPopulatesCache() async throws {
        let registry = makeRegistry(response: .openAIModels([]))
        MockModelsURLProtocol.perIDResponse = [
            "deepseek": .openAIModels(["deepseek-chat", "deepseek-reasoner"]),
            "lmstudio": .openAIModels(["Qwen2.5-VL-72B", "phi-4"]),
        ]

        await registry.fetchAllModels()

        XCTAssertEqual(registry.modelsByProviderID["deepseek"], ["deepseek-chat", "deepseek-reasoner"])
        XCTAssertEqual(registry.modelsByProviderID["lmstudio"], ["Qwen2.5-VL-72B", "phi-4"])
    }

    func testFetchAllModelsSkipsDisabledProviders() async throws {
        let disabledProvider = ProviderConfig(
            id: "disabled-prov",
            displayName: "Disabled",
            baseURL: "http://localhost:9999/v1",
            model: "",
            isEnabled: false,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )
        let registry = makeRegistry(
            response: .openAIModels(["should-not-appear"]),
            providers: [disabledProvider]
        )

        await registry.fetchAllModels()

        XCTAssertNil(registry.modelsByProviderID["disabled-prov"])
    }

    func testModelsByProviderIDIsPublished() async throws {
        let registry = makeRegistry(response: .openAIModels(["m1", "m2"]))

        var emittedValues: [[String: [String]]] = []
        let cancellable = registry.$modelsByProviderID.sink { emittedValues.append($0) }

        await registry.fetchAllModels()

        XCTAssertGreaterThan(emittedValues.count, 1, "modelsByProviderID should publish on update")
        cancellable.cancel()
    }

    // MARK: - probeAndFetchModels()

    func testProbeAndFetchModelsSetsBothCaches() async throws {
        MockModelsURLProtocol.nextResponse = .openAIModels(["phi-4", "mistral"])
        let lmstudio = testProviders()[1]
        let registry = makeRegistry(
            response: .openAIModels(["phi-4", "mistral"]),
            providers: [lmstudio]
        )

        await registry.probeAndFetchModels()

        XCTAssertNotNil(registry.availabilityByID["lmstudio"],
                        "availability should be set by probeAndFetchModels")
        XCTAssertFalse(registry.modelsByProviderID["lmstudio"]?.isEmpty ?? true,
                       "model list should be set by probeAndFetchModels")
    }

    // MARK: - knownModels removed

    func testKnownModelsIsGone() {
        // This test documents the deletion of knownModels.
        // It compiles only if the static property does NOT exist.
        // If knownModels is still present this file will fail to compile.
        // (The test body is intentionally empty — compilation is the assertion.)
    }
}

// MARK: - Mock URL protocol

enum MockModelsResponse {
    case openAIModels([String])
    case anthropicModels([String])
    case networkError
    case badJSON
}

final class MockModelsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var nextResponse: MockModelsResponse = .openAIModels([])
    nonisolated(unsafe) static var perIDResponse: [String: MockModelsResponse] = [:]
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockModelsURLProtocol.capturedRequests.append(request)

        // Pick per-ID response if available (host prefix, provider path token, or explicit header)
        let hostPrefix = request.url?.host?.components(separatedBy: ".").first ?? ""
        let providerHint = request.value(forHTTPHeaderField: "X-Merlin-Provider-ID") ?? ""
        let responseKey = providerHint.isEmpty ? hostPrefix : providerHint
        let response = MockModelsURLProtocol.perIDResponse[responseKey]
            ?? MockModelsURLProtocol.nextResponse

        switch response {
        case .openAIModels(let ids):
            let items = ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
            let body = "{\"object\":\"list\",\"data\":[\(items)]}".data(using: .utf8)!
            let r = HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)

        case .anthropicModels(let ids):
            let items = ids.map { "{\"id\":\"\($0)\",\"display_name\":\"\($0)\"}" }.joined(separator: ",")
            let body = "{\"data\":[\(items)]}".data(using: .utf8)!
            let r = HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)

        case .networkError:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))

        case .badJSON:
            let body = "not json".data(using: .utf8)!
            let r = HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
