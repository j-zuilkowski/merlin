import XCTest
@testable import Merlin

final class RealCatalogProviderAdaptersTests: XCTestCase {
    func testDigiKeyAdapterMapsRecordedFixtureIntoComponentCandidateEvidence() throws {
        let data = Data("""
        {"Products":[{"Manufacturer":{"Name":"onsemi"},"ManufacturerProductNumber":"MJ15003G","ProductDescription":"NPN power transistor","DatasheetUrl":"https://example.invalid/mj15003g.pdf","ProductUrl":"https://digikey.example/MJ15003G","LifecycleStatus":"Active","QuantityAvailable":42,"Parameters":[{"ParameterText":"Package / Case","ValueText":"TO-3"},{"ParameterText":"Power - Max","ValueText":"250 W"},{"ParameterText":"Voltage - Collector Emitter Breakdown (Max)","ValueText":"140 V"}]}]}
        """.utf8)

        let candidates = try DigiKeyCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "onsemi")
        XCTAssertEqual(candidate.mpn, "MJ15003G")
        XCTAssertEqual(candidate.package, "TO-3")
        XCTAssertEqual(candidate.ratings["power_max"], "250 W")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "digikey")
        XCTAssertEqual(candidate.evidence.first?.providerID, "digikey")
        XCTAssertEqual(candidate.evidence.first?.sourceURL, "https://digikey.example/MJ15003G")
    }

    func testDigiKeyAdapterMapsProductionNestedCategoryDescriptionAndPackageEvidence() throws {
        let data = Data("""
        {"Products":[{"Manufacturer":{"Name":"TE Connectivity Schaffner"},"ManufacturerProductNumber":"FN9222R-6-06","Description":{"ProductDescription":"PWR ENT RCPT IEC320-C14 PANEL QC","DetailedDescription":"Power Entry Connector Receptacle, Male Blades IEC 320-C14 Panel Mount, Flange"},"Category":{"Name":"Connectors, Interconnects","ChildCategories":[{"Name":"AC Power Connectors","ChildCategories":[{"Name":"Power Entry Modules (PEM)","ChildCategories":[]}]}]},"DatasheetUrl":"https://example.invalid/fn9222.pdf","ProductUrl":"https://digikey.example/FN9222R-6-06","ProductStatus":"Active","QuantityAvailable":12,"Parameters":[{"ParameterText":"Mounting Type","ValueText":"Panel Mount, Flange"},{"ParameterText":"Termination","ValueText":"Quick Connect - 0.250 in (6.3mm)"},{"ParameterText":"Voltage Rating - Filter","ValueText":"250VAC"}]}]}
        """.utf8)

        let candidates = try DigiKeyCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.normalizedCategory, "power_entry_modules_pem")
        XCTAssertEqual(candidate.package, "Panel Mount, Flange")
        XCTAssertEqual(candidate.ratings["termination"], "Quick Connect - 0.250 in (6.3mm)")
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/fn9222.pdf")
    }

    func testMouserAdapterMapsRecordedFixtureIntoComponentCandidateEvidence() throws {
        let data = Data("""
        {"SearchResults":{"Parts":[{"Manufacturer":"Yageo","ManufacturerPartNumber":"RC0603FR-0710KL","Description":"RES 10K OHM 1% 1/10W 0603","Category":"Resistors","DataSheetUrl":"https://example.invalid/rc0603.pdf","ProductDetailUrl":"https://mouser.example/RC0603","LifecycleStatus":"Active","Availability":"9,000 In Stock","ProductAttributes":[{"AttributeName":"Package / Case","AttributeValue":"0603"},{"AttributeName":"Resistance","AttributeValue":"10 kOhms"},{"AttributeName":"Power Rating","AttributeValue":"0.1 W"}]}]}}
        """.utf8)

        let candidates = try MouserCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "Yageo")
        XCTAssertEqual(candidate.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(candidate.normalizedCategory, "resistors")
        XCTAssertEqual(candidate.package, "0603")
        XCTAssertEqual(candidate.ratings["resistance"], "10 kOhms")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "mouser")
        XCTAssertEqual(candidate.evidence.first?.providerID, "mouser")
    }

    func testAggregatorAdapterMapsRecordedFixtureIntoLifecycleAndAvailabilityEvidence() throws {
        let data = Data("""
        {"parts":[{"manufacturer":"Texas Instruments","mpn":"NE5532P","category":"op_amp","package":"PDIP-8","lifecycle":"Active","availability":"Digi-Key: 100; Mouser: 200","datasheet_url":"https://example.invalid/ne5532.pdf","source_url":"https://aggregator.example/NE5532P","specs":{"supply_voltage":"30 V","channels":"2"}}]}
        """.utf8)

        let candidates = try AggregatorCatalogProviderAdapter(providerID: "octopart").mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.availabilitySummary, "Digi-Key: 100; Mouser: 200")
        XCTAssertEqual(candidate.ratings["supply_voltage"], "30 V")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "octopart")
        XCTAssertEqual(candidate.evidence.first?.providerID, "octopart")
    }

    func testNexarAdapterMapsGraphQLSearchResponseIntoComponentCandidateEvidence() throws {
        let data = Data("""
        {"data":{"supSearchMpn":{"results":[{"description":"NPN power transistor","part":{"name":"MJ15003G","mpn":"MJ15003G","shortDescription":"NPN transistor","totalAvail":128,"manufacturer":{"name":"onsemi","homepageUrl":"https://www.onsemi.com"},"category":{"name":"Bipolar Transistors"},"specs":[{"attribute":{"name":"Package / Case","shortname":"Package / Case"},"displayValue":"TO-3"},{"attribute":{"name":"Power - Max","shortname":"Power - Max"},"displayValue":"250 W"},{"attribute":{"name":"Lifecycle Status","shortname":"Lifecycle Status"},"displayValue":"Active"}],"bestDatasheet":{"url":"https://example.invalid/mj15003g.pdf"},"sellers":[{"company":{"name":"Digi-Key"},"offers":[{"inventoryLevel":50}]},{"company":{"name":"Mouser"},"offers":[{"inventoryLevel":78}]}]}}]}}}
        """.utf8)

        let candidates = try NexarCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "onsemi")
        XCTAssertEqual(candidate.mpn, "MJ15003G")
        XCTAssertEqual(candidate.normalizedCategory, "bipolar_transistors")
        XCTAssertEqual(candidate.package, "TO-3")
        XCTAssertEqual(candidate.ratings["power_max"], "250 W")
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.availabilitySummary, "128 total available")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "nexar")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/mj15003g.pdf")
        XCTAssertEqual(candidate.evidence.first?.providerID, "nexar")
        XCTAssertEqual(candidate.evidence.first?.sourceURL, "https://www.onsemi.com")
    }

    func testMissingCredentialsDisableLiveProvidersCleanly() {
        let digikey = CatalogProviderCredentialPolicy(
            providerID: "digikey",
            requiredCredentialKeys: ["DIGIKEY_CLIENT_ID", "DIGIKEY_CLIENT_SECRET"],
            environment: [:]
        )
        let mouser = CatalogProviderCredentialPolicy(
            providerID: "mouser",
            requiredCredentialKeys: ["MOUSER_API_KEY"],
            environment: ["MOUSER_API_KEY": "fixture-key"]
        )

        XCTAssertFalse(digikey.liveProviderEnabled)
        XCTAssertEqual(digikey.missingCredentialKeys, ["DIGIKEY_CLIENT_ID", "DIGIKEY_CLIENT_SECRET"])
        XCTAssertTrue(mouser.liveProviderEnabled)
        XCTAssertTrue(mouser.missingCredentialKeys.isEmpty)
    }

    func testLiveAPITestsAreOptInAndNotRequiredForFocusedVerification() {
        XCTAssertFalse(RealCatalogLiveTestPolicy(environment: [:]).shouldRunLiveTests)
        XCTAssertTrue(RealCatalogLiveTestPolicy(environment: ["MERLIN_LIVE_CATALOG_TESTS": "1"]).shouldRunLiveTests)
    }

    func testLiveMouserProviderBuildsKeywordRequestAndMapsCachedEvidenceShape() async throws {
        let response = Data("""
        {"SearchResults":{"Parts":[{"Manufacturer":"Yageo","ManufacturerPartNumber":"RC0603FR-0710KL","Description":"RES 10K OHM 1% 1/10W 0603","Category":"Resistors","DataSheetUrl":"https://example.invalid/rc0603.pdf","ProductDetailUrl":"https://mouser.example/RC0603","LifecycleStatus":"Active","Availability":"9,000 In Stock","ProductAttributes":[{"AttributeName":"Package / Case","AttributeValue":"0603"},{"AttributeName":"Resistance","AttributeValue":"10 kOhms"}]}]}}
        """.utf8)
        let transport = MockCatalogHTTPTransport(responses: [response])
        let provider = LiveMouserCatalogProvider(
            apiKey: "test-key",
            endpoint: URL(string: "https://api.mouser.test/api/v2/search/keyword")!,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = try await provider.searchWithRawResponse(ComponentSearchRequest(
            refdes: "RFILT1",
            role: "sweepable filter resistor",
            constraints: ["selected_symbol": "Device:R"],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("apiKey=test-key"))
        let body = try XCTUnwrap(request.httpBody).utf8String
        XCTAssertTrue(body.contains("resistor"))
        XCTAssertFalse(body.contains("Device:R"))
        XCTAssertEqual(result.candidates.first?.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(result.candidates.first?.evidence.first?.cachePolicy, "live_api")
        XCTAssertEqual(result.rawResponse, response)
    }

    func testLiveDigiKeyProviderUsesClientCredentialsThenKeywordSearch() async throws {
        let token = Data(#"{"access_token":"token-123","expires_in":1800}"#.utf8)
        let search = Data("""
        {"Products":[{"Manufacturer":{"Name":"onsemi"},"ManufacturerProductNumber":"MJ15003G","ProductDescription":"NPN power transistor","DatasheetUrl":"https://example.invalid/mj15003g.pdf","ProductUrl":"https://digikey.example/MJ15003G","LifecycleStatus":"Active","QuantityAvailable":42,"Parameters":[{"ParameterText":"Package / Case","ValueText":"TO-3"},{"ParameterText":"Power - Max","ValueText":"250 W"}]}]}
        """.utf8)
        let transport = MockCatalogHTTPTransport(responses: [token, search])
        let provider = LiveDigiKeyCatalogProvider(
            clientID: "client-id",
            clientSecret: "client-secret",
            searchEndpoint: URL(string: "https://api.digikey.test/products/v4/search/keyword")!,
            tokenEndpoint: URL(string: "https://api.digikey.test/v1/oauth2/token")!,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = try await provider.searchWithRawResponse(ComponentSearchRequest(
            refdes: "QOUT1",
            role: "single-ended Class-A output transistor",
            constraints: ["manufacturer_part_number": "MJ15003G"],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertEqual(transport.requests.count, 2)
        let tokenRequest = transport.requests[0]
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(try XCTUnwrap(tokenRequest.httpBody).utf8String.contains("grant_type=client_credentials"))

        let searchRequest = transport.requests[1]
        XCTAssertEqual(searchRequest.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
        XCTAssertEqual(searchRequest.value(forHTTPHeaderField: "X-DIGIKEY-Client-Id"), "client-id")
        XCTAssertTrue(try XCTUnwrap(searchRequest.httpBody).utf8String.contains("MJ15003G"))
        XCTAssertEqual(result.candidates.first?.mpn, "MJ15003G")
        XCTAssertEqual(result.candidates.first?.evidence.first?.cachePolicy, "live_api")
    }

    func testLiveNexarProviderUsesClientCredentialsThenGraphQLSearch() async throws {
        let token = Data(#"{"access_token":"nexar-token","expires_in":86400}"#.utf8)
        let search = Data("""
        {"data":{"supSearchMpn":{"results":[{"description":"NPN power transistor","part":{"name":"MJ15003G","mpn":"MJ15003G","shortDescription":"NPN transistor","totalAvail":128,"manufacturer":{"name":"onsemi","homepageUrl":"https://www.onsemi.com"},"category":{"name":"Bipolar Transistors"},"specs":[{"attribute":{"name":"Package / Case","shortname":"Package / Case"},"displayValue":"TO-3"},{"attribute":{"name":"Power - Max","shortname":"Power - Max"},"displayValue":"250 W"}],"bestDatasheet":{"url":"https://example.invalid/mj15003g.pdf"},"sellers":[]}}]}}}
        """.utf8)
        let transport = MockCatalogHTTPTransport(responses: [token, search])
        let provider = LiveNexarCatalogProvider(
            clientID: "client-id",
            clientSecret: "client-secret",
            graphqlEndpoint: URL(string: "https://api.nexar.test/graphql/")!,
            tokenEndpoint: URL(string: "https://identity.nexar.test/connect/token")!,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = try await provider.searchWithRawResponse(ComponentSearchRequest(
            refdes: "QOUT1",
            role: "single-ended Class-A output transistor",
            constraints: ["manufacturer_part_number": "MJ15003G"],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertEqual(transport.requests.count, 2)
        let tokenRequest = transport.requests[0]
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(try XCTUnwrap(tokenRequest.httpBody).utf8String.contains("grant_type=client_credentials"))
        XCTAssertTrue(try XCTUnwrap(tokenRequest.httpBody).utf8String.contains("scope=supply.domain"))

        let searchRequest = transport.requests[1]
        XCTAssertEqual(searchRequest.value(forHTTPHeaderField: "Authorization"), "Bearer nexar-token")
        XCTAssertTrue(try XCTUnwrap(searchRequest.httpBody).utf8String.contains("supSearchMpn"))
        XCTAssertTrue(try XCTUnwrap(searchRequest.httpBody).utf8String.contains("MJ15003G"))
        XCTAssertEqual(result.candidates.first?.mpn, "MJ15003G")
        XCTAssertEqual(result.candidates.first?.evidence.first?.cachePolicy, "live_api")
        XCTAssertEqual(result.rawResponse, search)
    }

    func testLiveCatalogQueryCachePersistsNormalizedAndRawProviderResponses() throws {
        let root = try temporaryDirectory()
        let cache = LiveCatalogQueryCache()
        let candidate = ComponentCandidate(
            mpn: "RC0603FR-0710KL",
            manufacturer: "Yageo",
            normalizedCategory: "resistors",
            value: nil,
            package: "0603",
            ratings: ["resistance": "10 kOhms"],
            lifecycleState: "Active",
            availabilitySummary: "9,000 In Stock",
            datasheets: [DatasheetEvidence(manufacturer: "Yageo", mpn: "RC0603FR-0710KL", url: "https://example.invalid/rc0603.pdf", localPath: nil, sha256: nil, providerID: "mouser", retrievedAt: "test", license: "test", citations: [])],
            evidence: [ComponentEvidence(providerID: "mouser", sourceURL: nil, localPath: nil, retrievedAt: "test", cachePolicy: "live_api", sha256: nil, extractedParameters: ["package": "0603"], confidence: 1.0, warnings: [])],
            footprintCandidates: []
        )

        try cache.write(
            candidates: [candidate],
            rawResponse: Data(#"{"SearchResults":{"Parts":[]}}"#.utf8),
            providerID: "mouser",
            query: "Device:R",
            requestURL: URL(string: "https://api.mouser.test/search"),
            to: root,
            now: Date(timeIntervalSince1970: 1_000)
        )

        let loaded = try cache.loadCandidates(
            providerID: "mouser",
            query: "Device:R",
            from: root,
            maxAgeSeconds: 60,
            now: Date(timeIntervalSince1970: 1_030)
        )
        XCTAssertEqual(loaded?.first?.mpn, "RC0603FR-0710KL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.rawURL(providerID: "mouser", query: "Device:R", directory: root).path))
        let stale = try cache.loadCandidates(
            providerID: "mouser",
            query: "Device:R",
            from: root,
            maxAgeSeconds: 60,
            now: Date(timeIntervalSince1970: 1_061)
        )
        XCTAssertNil(stale)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-live-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class MockCatalogHTTPTransport: CatalogHTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var responses: [Data]

    init(responses: [Data]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let data = responses.isEmpty ? Data() : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
