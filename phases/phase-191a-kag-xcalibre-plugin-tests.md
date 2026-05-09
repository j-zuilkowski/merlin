# Phase 191a — KAG XcalibrePlugin + RAGTools + AppSettings Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 190b complete: KAGBackendPlugin protocol, NullKAGPlugin, LocalKAGPlugin, KAGEngine stub.

New surface introduced in phase 191b:
  - `XcalibreKAGPlugin` — `KAGBackendPlugin` implementation that talks to xcalibre-server:
      `init(baseURL: URL, token: String, session: URLSession)`
      `writeTriples` → `POST /api/v1/graph/triples` (bearer auth)
      `traverse`     → `GET  /api/v1/graph/traverse?anchor=…&hops=…[&domain_id=…]`
  - `KAGEngine.extractTriples(text:domain:)` — real implementation: calls the chat LLM
    with a compact JSON-extraction prompt; parses `[{subject, predicate, object}]` array;
    falls back silently to [] on any error or malformed response; timeout 10 s
  - `AppSettings` additions:
      `kagEnabled: Bool` (default false, key `kag_enabled`, config path `[kag] enabled`)
      `kagHops: Int`    (default 2, key `kag_hops`, config path `[kag] hops`)
      `kagXcalibreURL: String` (default "", key `kag_xcalibre_url`)
  - Startup wiring in `AppDelegate` or `AppState.init`: when `kagEnabled && !kagXcalibreURL.isEmpty`,
    construct `XcalibreKAGPlugin` and register it via `KAGBackendRegistry.shared.register(plugin)`;
    otherwise register `LocalKAGPlugin`
  - `RAGTools.buildEnrichedMessage` — appends a `## Knowledge Graph` section to the context
    message when the active plugin returns a non-empty `traverse` result for the query

TDD coverage:
  File 1 — XcalibreKAGPluginTests: writeTriples sends correct POST body; traverse builds
    correct GET URL; 401 response throws; network error propagates
  File 2 — KAGEngineExtractionTests: extractTriples parses valid JSON array; returns []
    on invalid JSON; returns [] on empty LLM response
  File 3 — AppSettingsKAGTests: kagEnabled defaults false; kagHops defaults 2;
    round-trip persist and reload
  File 4 — RAGToolsEnrichmentTests: buildEnrichedMessage appends graph section when
    traverse returns triples; omits section when traverse returns []

---

## Write to: MerlinTests/Unit/XcalibreKAGPluginTests.swift

```swift
import XCTest
@testable import Merlin

final class XcalibreKAGPluginTests: XCTestCase {

    // MARK: - Helpers

    private func makePlugin(
        handler: @escaping (URLRequest) -> (Data, URLResponse)
    ) -> XcalibreKAGPlugin {
        let session = URLSession.mock(handler: handler)
        return XcalibreKAGPlugin(
            baseURL: URL(string: "http://xcalibre.local")!,
            token: "test-token",
            session: session
        )
    }

    // MARK: - writeTriples

    func test_writeTriples_sends_post_with_correct_body() async throws {
        var capturedRequest: URLRequest?

        let plugin = makePlugin { req in
            capturedRequest = req
            let body = """
            {"written":1}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        let triple = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                               domainId: "electronics", source: .session, confidence: 0.9)
        try await plugin.writeTriples([triple])

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.url?.path == "/api/v1/graph/triples")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

        let bodyData = try XCTUnwrap(req.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let triples = json?["triples"] as? [[String: Any]]
        XCTAssertEqual(triples?.count, 1)
        XCTAssertEqual(triples?.first?["subject"] as? String, "U4")
        XCTAssertEqual(triples?.first?["predicate"] as? String, "shares_net")
        XCTAssertEqual(triples?.first?["object"] as? String, "VCC")
    }

    func test_writeTriples_throws_on_401() async {
        let plugin = makePlugin { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }

        do {
            try await plugin.writeTriples([
                KAGTriple(subject: "A", predicate: "b", object: "C",
                          domainId: "", source: .session, confidence: 1.0)
            ])
            XCTFail("Expected throw on 401")
        } catch {
            // expected
        }
    }

    // MARK: - traverse

    func test_traverse_builds_correct_url() async throws {
        var capturedRequest: URLRequest?

        let plugin = makePlugin { req in
            capturedRequest = req
            let body = """
            {"triples":[]}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        _ = try await plugin.traverse(anchor: "FnA", hops: 2, domainId: "software")

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "GET")
        let urlStr = req.url?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("/api/v1/graph/traverse"))
        XCTAssertTrue(urlStr.contains("anchor=FnA"))
        XCTAssertTrue(urlStr.contains("hops=2"))
        XCTAssertTrue(urlStr.contains("domain_id=software"))
    }

    func test_traverse_returns_parsed_triples() async throws {
        let plugin = makePlugin { req in
            let body = """
            {"triples":[
                {"subject":"FnA","predicate":"calls","object":"FnB",
                 "domain_id":"software","source":"session","confidence":0.9,
                 "id":"1","source_id":"s1","chunk_index":null,"created_at":0}
            ]}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.subject, "FnA")
        XCTAssertEqual(result.first?.predicate, "calls")
    }

    func test_traverse_throws_on_network_error() async {
        let session = URLSession.mock { _ in
            throw URLError(.notConnectedToInternet)
        }
        let plugin = XcalibreKAGPlugin(
            baseURL: URL(string: "http://xcalibre.local")!,
            token: "tok",
            session: session
        )

        do {
            _ = try await plugin.traverse(anchor: "A", hops: 1, domainId: nil)
            XCTFail("Expected throw on network error")
        } catch {
            // expected
        }
    }
}

// MARK: - URLSession mock helper

extension URLSession {
    static func mock(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) -> URLSession {
        MockURLSession.register(handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MockURLProtocol must be accessible from test target — add to TestHelpers/ if needed.
// For now declare it here:
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Data, URLResponse))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

enum MockURLSession {
    static func register(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        MockURLProtocol.handler = handler
    }
}
```

---

## Write to: MerlinTests/Unit/KAGEngineExtractionTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class KAGEngineExtractionTests: XCTestCase {

    func test_extractTriples_parses_valid_json_array() {
        // In 191b KAGEngine.extractTriples accepts an LLM JSON string directly for unit testing.
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let json = """
        [
          {"subject":"U4","predicate":"shares_net","object":"VCC"},
          {"subject":"VCC","predicate":"connects","object":"C12"}
        ]
        """
        let result = engine.parseExtractedTriples(json: json, domain: "electronics")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].subject, "U4")
        XCTAssertEqual(result[0].predicate, "shares_net")
        XCTAssertEqual(result[0].domainId, "electronics")
        XCTAssertEqual(result[0].source, .session)
    }

    func test_extractTriples_returns_empty_on_invalid_json() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let result = engine.parseExtractedTriples(json: "not json at all", domain: "test")
        XCTAssertTrue(result.isEmpty)
    }

    func test_extractTriples_returns_empty_on_empty_string() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let result = engine.parseExtractedTriples(json: "", domain: "test")
        XCTAssertTrue(result.isEmpty)
    }

    func test_extractTriples_skips_incomplete_triples() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        // Missing "object" in second item
        let json = """
        [
          {"subject":"A","predicate":"b","object":"C"},
          {"subject":"D","predicate":"e"}
        ]
        """
        let result = engine.parseExtractedTriples(json: json, domain: "x")
        XCTAssertEqual(result.count, 1, "Only complete triples should be returned")
    }
}
```

---

## Write to: MerlinTests/Unit/AppSettingsKAGTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class AppSettingsKAGTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        // Use a temp config path so we don't pollute the real ~/.merlin/config.toml
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-kag-test-\(UUID().uuidString).toml")
        return AppSettings(configURL: tmp)
    }

    func test_kagEnabled_defaults_false() {
        let settings = makeSettings()
        XCTAssertFalse(settings.kagEnabled)
    }

    func test_kagHops_defaults_2() {
        let settings = makeSettings()
        XCTAssertEqual(settings.kagHops, 2)
    }

    func test_kagXcalibreURL_defaults_empty() {
        let settings = makeSettings()
        XCTAssertTrue(settings.kagXcalibreURL.isEmpty)
    }

    func test_kagEnabled_roundtrip() throws {
        let settings = makeSettings()
        settings.kagEnabled = true
        try settings.save()

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertTrue(reloaded.kagEnabled)
    }

    func test_kagHops_roundtrip() throws {
        let settings = makeSettings()
        settings.kagHops = 3
        try settings.save()

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertEqual(reloaded.kagHops, 3)
    }
}
```

---

## Write to: MerlinTests/Unit/RAGToolsEnrichmentTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class RAGToolsEnrichmentTests: XCTestCase {

    func test_buildEnrichedMessage_appends_graph_section_when_triples_present() async throws {
        let plugin = StubKAGPlugin(triples: [
            KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                      domainId: "electronics", source: .session, confidence: 0.9)
        ])
        let registry = KAGBackendRegistry()
        registry.register(plugin)

        let message = await RAGTools.buildEnrichedMessage(
            query: "U4 decoupling",
            chunks: [],
            registry: registry,
            hops: 1,
            domainId: nil
        )

        XCTAssertTrue(message.contains("## Knowledge Graph"),
                      "Must contain Knowledge Graph section")
        XCTAssertTrue(message.contains("U4"),
                      "Must include triple subject")
    }

    func test_buildEnrichedMessage_omits_graph_section_when_empty() async throws {
        let plugin = StubKAGPlugin(triples: [])
        let registry = KAGBackendRegistry()
        registry.register(plugin)

        let message = await RAGTools.buildEnrichedMessage(
            query: "anything",
            chunks: [],
            registry: registry,
            hops: 1,
            domainId: nil
        )

        XCTAssertFalse(message.contains("## Knowledge Graph"),
                       "Must NOT contain Knowledge Graph section when traverse returns []")
    }
}

// MARK: - Stub

private final class StubKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    let triples: [KAGTriple]
    init(triples: [KAGTriple]) { self.triples = triples }
    func writeTriples(_ triples: [KAGTriple]) async throws {}
    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return triples
    }
}
```

---

## Verify (tests must FAIL)

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD FAILED — missing symbols `XcalibreKAGPlugin`, `KAGEngine.parseExtractedTriples`,
`AppSettings.kagEnabled`, `AppSettings.kagHops`, `AppSettings.kagXcalibreURL`,
`RAGTools.buildEnrichedMessage(query:chunks:registry:hops:domainId:)`. Correct failing state.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add \
  MerlinTests/Unit/XcalibreKAGPluginTests.swift \
  MerlinTests/Unit/KAGEngineExtractionTests.swift \
  MerlinTests/Unit/AppSettingsKAGTests.swift \
  MerlinTests/Unit/RAGToolsEnrichmentTests.swift
git commit -m "Phase 191a — KAG XcalibrePlugin + RAGTools + AppSettings tests (failing)"
```
