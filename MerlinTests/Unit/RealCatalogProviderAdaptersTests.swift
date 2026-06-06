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

    func testMouserAdapterMapsAlternateDatasheetAndPackageEvidence() throws {
        let data = Data("""
        {"SearchResults":{"Parts":[{"Manufacturer":"Comchip Technology","ManufacturerPartNumber":"GBU810-G","Description":"Bridge Rectifiers 100 Volt 8.0 Amp Glass Passivated GBU Through Hole","Category":"Bridge Rectifiers","DatasheetURL":"https://example.invalid/gbu810.pdf","ProductDetailUrl":"https://mouser.example/GBU810-G","LifecycleStatus":"Active","Availability":"27 In Stock","PackageType":"GBU","ProductAttributes":[{"AttributeName":"Voltage Rating","AttributeValue":"100 V"},{"AttributeName":"Current Rating","AttributeValue":"8 A"},{"AttributeName":"Mounting Style","AttributeValue":"Through Hole"}]}]}}
        """.utf8)

        let candidates = try MouserCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.package, "GBU")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/gbu810.pdf")
        XCTAssertEqual(candidate.ratings["voltage_v"], "100")
        XCTAssertEqual(candidate.ratings["current_a"], "8.0")
    }

    func testCatalogQueryBuilderKeepsGenericPassiveFallbacksBroad() throws {
        let builder = CatalogSearchQueryBuilder()
        let queries = builder.keywords(for: ComponentSearchRequest(
            refdes: "RTREBLE1",
            role: "treble shelf network resistor",
            constraints: [
                "component_category": "resistor",
                "resistance": "250kOhm",
                "power_rating": "0.25W",
                "tolerance": "1%",
                "mounting": "through_hole",
                "selected_symbol": "Device:R",
            ],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertTrue(queries.contains("resistor 250kOhm 0.25W 1% through hole"))
        XCTAssertFalse(queries.first?.contains("treble") ?? true)
        XCTAssertTrue(queries.contains("resistor 250kOhm"))
        XCTAssertTrue(queries.contains("fixed resistor 250kOhm"))
        XCTAssertTrue(queries.contains("metal film resistor 250kOhm"))
        XCTAssertTrue(queries.contains("resistor 250kOhm 1%"))
        XCTAssertTrue(queries.contains("fixed resistor 250kOhm 1%"))
        XCTAssertTrue(queries.contains("resistor 250kOhm 0.25W"))
        XCTAssertTrue(queries.contains("fixed resistor 250kOhm 0.25W"))
        XCTAssertTrue(queries.contains("through hole fixed resistor 250kOhm"))
        XCTAssertTrue(queries.contains("axial resistor 250kOhm"))
    }

    func testCatalogQueryBuilderAddsBroadFallbacksForPowerTransistorsAndConnectors() throws {
        let builder = CatalogSearchQueryBuilder()

        let transistorQueries = builder.keywords(for: ComponentSearchRequest(
            refdes: "QOUT1",
            role: "single-ended Class-A output transistor",
            constraints: [
                "component_category": "power_transistor",
                "polarity": "NPN",
                "voltage_rating": "80V",
                "current_rating": "8A",
                "power_rating": "100W",
                "package": "TO-3_or_TO-247",
            ],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertFalse(transistorQueries.first?.contains("single") ?? true)
        XCTAssertTrue(transistorQueries.contains("NPN power transistor"))
        XCTAssertTrue(transistorQueries.contains("NPN power transistor 100W"))
        XCTAssertTrue(transistorQueries.contains("NPN power transistor TO-3"))

        let connectorQueries = builder.keywords(for: ComponentSearchRequest(
            refdes: "JSEC",
            role: "isolated transformer secondary input connector",
            constraints: [
                "component_category": "terminal_block",
                "positions": "2",
                "current_rating": "10A",
                "voltage_rating": "300V",
                "mounting": "through_hole",
            ],
            requiredEvidenceTypes: [],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertTrue(connectorQueries.contains("2 position terminal block"))
        XCTAssertTrue(connectorQueries.contains("terminal block 10A"))
        XCTAssertFalse(connectorQueries.first?.contains("isolated") ?? true)
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

    func testTrustedPartsAdapterMapsAuthorizedInventoryEvidence() throws {
        let data = Data("""
        {"Results":[{"SearchToken":"MJ15003G","Parts":[{"Manufacturer":"onsemi","ManufacturerPartNumber":"MJ15003G","Description":"NPN Bipolar Transistor 140V 20A 250W TO-3","Category":"Bipolar Transistors","DatasheetUrl":"https://example.invalid/mj15003g.pdf","ProductUrl":"https://trustedparts.example/MJ15003G","LifecycleStatus":"Active","Package":"TO-3","Parameters":[{"Name":"Package / Case","Value":"TO-3"},{"Name":"Power - Max","Value":"250 W"},{"Name":"Voltage - Collector Emitter Breakdown (Max)","Value":"140 V"},{"Name":"Current - Collector (Ic) (Max)","Value":"20 A"}],"Offers":[{"Distributor":"Digi-Key","QuantityAvailable":50,"BuyUrl":"https://digikey.example/MJ15003G","Packaging":"Tube","Moq":1,"LeadTime":"0 weeks"}]}]}]}
        """.utf8)

        let candidates = try TrustedPartsCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "onsemi")
        XCTAssertEqual(candidate.mpn, "MJ15003G")
        XCTAssertEqual(candidate.normalizedCategory, "bipolar_transistors")
        XCTAssertEqual(candidate.package, "TO-3")
        XCTAssertEqual(candidate.ratings["power_max"], "250 W")
        XCTAssertEqual(candidate.ratings["voltage_v"], "140 V")
        XCTAssertEqual(candidate.ratings["current_a"], "20 A")
        XCTAssertEqual(candidate.ratings["packaging"], "Tube")
        XCTAssertEqual(candidate.ratings["moq"], "1")
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.availabilitySummary, "Digi-Key: 50")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "trustedparts")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/mj15003g.pdf")
        XCTAssertEqual(candidate.evidence.first?.providerID, "trustedparts")
        XCTAssertEqual(candidate.evidence.first?.sourceURL, "https://trustedparts.example/MJ15003G")
    }

    func testOnsemiAdapterMapsProductPageIntoManufacturerFallbackEvidence() throws {
        let data = Data("""
        <html><body>
        <h1>Audio Transistors | MJ15003</h1>
        <h2>Bipolar Transistor, NPN, 140 V, 20 A</h2>
        <a href="/download/data-sheet/pdf/mj15003-d.pdf">Datasheet</a>
        <table>
        <tr><th>Product</th><th>Status</th><th>Package Type</th><th>Polarity</th><th>I_C Continuous (A)</th><th>V CEO(sus) Min (V)</th><th>P_TM Max (W)</th></tr>
        <tr><td>MJ15003G</td><td>Active</td><td>TO-204-2</td><td>NPN</td><td>20</td><td>140</td><td>250</td></tr>
        </table>
        </body></html>
        """.utf8)

        let candidates = try OnsemiCatalogProviderAdapter().mapProductPage(
            data,
            sourceURL: URL(string: "https://www.onsemi.com/products/discrete-power-modules/audio-transistors/mj15003")!,
            requestedMPN: "MJ15003G"
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "onsemi")
        XCTAssertEqual(candidate.mpn, "MJ15003G")
        XCTAssertEqual(candidate.normalizedCategory, "audio_transistors")
        XCTAssertEqual(candidate.package, "TO-204-2")
        XCTAssertEqual(candidate.ratings["voltage_v"], "140 V")
        XCTAssertEqual(candidate.ratings["current_a"], "20 A")
        XCTAssertEqual(candidate.ratings["power_w"], "250 W")
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.availabilitySummary, "manufacturer evidence only")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "onsemi")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://www.onsemi.com/download/data-sheet/pdf/mj15003-d.pdf")
        XCTAssertEqual(candidate.evidence.first?.providerID, "onsemi")
        XCTAssertEqual(candidate.evidence.first?.warnings, ["manufacturer_fallback_no_stock_pricing"])
    }

    func testVendorFeedAdapterMapsCSVExportIntoStrictEvidence() throws {
        let data = Data("""
        Manufacturer,MPN,Description,Category,Package,Voltage,Current,Power,Datasheet URL,Product URL,Availability,Distributor,MOQ,Packaging,Lead Time,Lifecycle
        onsemi,MJ15003G,"NPN Bipolar Transistor 140V 20A 250W TO-3",Bipolar Transistors,TO-3,140 V,20 A,250 W,https://example.invalid/mj15003g.pdf,https://vendor.example/MJ15003G,50,Digi-Key,1,Tube,0 weeks,Active
        """.utf8)

        let candidates = try VendorFeedCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "onsemi")
        XCTAssertEqual(candidate.mpn, "MJ15003G")
        XCTAssertEqual(candidate.normalizedCategory, "bipolar_transistors")
        XCTAssertEqual(candidate.package, "TO-3")
        XCTAssertEqual(candidate.ratings["voltage_v"], "140 V")
        XCTAssertEqual(candidate.ratings["current_a"], "20 A")
        XCTAssertEqual(candidate.ratings["power_w"], "250 W")
        XCTAssertEqual(candidate.ratings["moq"], "1")
        XCTAssertEqual(candidate.availabilitySummary, "Digi-Key: 50")
        XCTAssertEqual(candidate.datasheets.first?.providerID, "vendor_feed")
        XCTAssertEqual(candidate.evidence.first?.providerID, "vendor_feed")
        XCTAssertEqual(candidate.evidence.first?.sourceURL, "https://vendor.example/MJ15003G")
    }

    func testVendorFeedAdapterMapsJSONExportIntoStrictEvidence() throws {
        let data = Data("""
        {"parts":[{"manufacturer":"Yageo","mpn":"RC0603FR-0710KL","description":"RES 10K OHM 1% 1/10W 0603","category":"Resistors","package":"0603","ratings":{"resistance":"10 kOhms","power":"0.1 W"},"datasheet_url":"https://example.invalid/rc0603.pdf","source_url":"https://vendor.example/RC0603","availability":"Mouser: 9000","lifecycle":"Active"}]}
        """.utf8)

        let candidates = try VendorFeedCatalogProviderAdapter().mapRecordedResponse(data)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.manufacturer, "Yageo")
        XCTAssertEqual(candidate.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(candidate.package, "0603")
        XCTAssertEqual(candidate.ratings["resistance"], "10 kOhms")
        XCTAssertEqual(candidate.ratings["power_w"], "0.1 W")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/rc0603.pdf")
        XCTAssertEqual(candidate.evidence.first?.providerID, "vendor_feed")
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

    func testLiveMouserProviderSurfacesRateLimitWithRetryAfter() async throws {
        let transport = MockCatalogHTTPTransport(responses: [
            .init(data: Data(#"{"error":"rate limited"}"#.utf8), statusCode: 429, headers: ["Retry-After": "42"]),
        ])
        let provider = LiveMouserCatalogProvider(
            apiKey: "test-key",
            endpoint: URL(string: "https://api.mouser.test/api/v2/search/keyword")!,
            transport: transport
        )

        do {
            _ = try await provider.searchWithRawResponse(ComponentSearchRequest(
                refdes: "R1",
                role: "bias resistor",
                constraints: ["component_category": "resistor", "resistance": "10kOhm"],
                requiredEvidenceTypes: [],
                preferredVendors: [],
                excludedManufacturers: [],
                lifecyclePolicy: "active"
            ))
            XCTFail("Expected rate limit error.")
        } catch LiveCatalogProviderError.rateLimited(let retryAfterSeconds) {
            XCTAssertEqual(retryAfterSeconds, 42)
        } catch {
            XCTFail("Expected rate limit error, got \(error).")
        }
    }

    func testLiveDigiKeyProviderSurfacesRateLimitWithRetryAfter() async throws {
        let transport = MockCatalogHTTPTransport(responses: [
            .init(data: Data(#"{"error":"rate limited"}"#.utf8), statusCode: 429, headers: ["Retry-After": "17"]),
        ])
        let provider = LiveDigiKeyCatalogProvider(
            clientID: "client-id",
            accessToken: "token",
            searchEndpoint: URL(string: "https://api.digikey.test/products/v4/search/keyword")!,
            transport: transport
        )

        do {
            _ = try await provider.searchWithRawResponse(rateLimitSearchRequest())
            XCTFail("Expected rate limit error.")
        } catch LiveCatalogProviderError.rateLimited(let retryAfterSeconds) {
            XCTAssertEqual(retryAfterSeconds, 17)
        } catch {
            XCTFail("Expected rate limit error, got \(error).")
        }
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

    func testLiveNexarProviderSurfacesRateLimitWithRetryAfter() async throws {
        let transport = MockCatalogHTTPTransport(responses: [
            .init(data: Data(#"{"error":"rate limited"}"#.utf8), statusCode: 429, headers: ["Retry-After": "23"]),
        ])
        let provider = LiveNexarCatalogProvider(
            clientID: "client-id",
            accessToken: "token",
            graphqlEndpoint: URL(string: "https://api.nexar.test/graphql/")!,
            transport: transport
        )

        do {
            _ = try await provider.searchWithRawResponse(rateLimitSearchRequest())
            XCTFail("Expected rate limit error.")
        } catch LiveCatalogProviderError.rateLimited(let retryAfterSeconds) {
            XCTAssertEqual(retryAfterSeconds, 23)
        } catch {
            XCTFail("Expected rate limit error, got \(error).")
        }
    }

    func testLiveTrustedPartsProviderBuildsConservativeInventoryRequest() async throws {
        let search = Data("""
        {"Results":[{"SearchToken":"MJ15003G","Parts":[{"Manufacturer":"onsemi","ManufacturerPartNumber":"MJ15003G","Description":"NPN Bipolar Transistor 140V 20A 250W TO-3","Category":"Bipolar Transistors","DatasheetUrl":"https://example.invalid/mj15003g.pdf","ProductUrl":"https://trustedparts.example/MJ15003G","LifecycleStatus":"Active","Package":"TO-3","Parameters":[{"Name":"Package / Case","Value":"TO-3"},{"Name":"Power - Max","Value":"250 W"}],"Offers":[{"Distributor":"Digi-Key","QuantityAvailable":50}]}]}]}
        """.utf8)
        let transport = MockCatalogHTTPTransport(responses: [search])
        let provider = LiveTrustedPartsCatalogProvider(
            companyID: "company-id",
            apiKey: "api-key",
            endpoint: URL(string: "https://api.trustedparts.test/v2/search")!,
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

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let body = try XCTUnwrap(request.httpBody).utf8String
        XCTAssertTrue(body.contains("CompanyId"))
        XCTAssertTrue(body.contains("company-id"))
        XCTAssertTrue(body.contains("ApiKey"))
        XCTAssertTrue(body.contains("api-key"))
        XCTAssertTrue(body.contains("Queries"))
        XCTAssertTrue(body.contains("MJ15003G"))
        XCTAssertTrue(body.contains("ExactMatch"))
        XCTAssertTrue(body.contains("InStockOnly"))
        XCTAssertTrue(body.contains("UserAgent"))
        XCTAssertFalse(body.contains("SourceIp"))
        XCTAssertEqual(result.candidates.first?.mpn, "MJ15003G")
        XCTAssertEqual(result.candidates.first?.evidence.first?.cachePolicy, "live_api")
        XCTAssertEqual(result.rawResponse, search)
    }

    func testLiveTrustedPartsProviderSurfacesRateLimitWithRetryAfter() async throws {
        let transport = MockCatalogHTTPTransport(responses: [
            .init(data: Data(#"{"error":"rate limited"}"#.utf8), statusCode: 429, headers: ["Retry-After": "31"]),
        ])
        let provider = LiveTrustedPartsCatalogProvider(
            companyID: "company-id",
            apiKey: "api-key",
            endpoint: URL(string: "https://api.trustedparts.test/v2/search")!,
            transport: transport
        )

        do {
            _ = try await provider.searchWithRawResponse(rateLimitSearchRequest())
            XCTFail("Expected rate limit error.")
        } catch LiveCatalogProviderError.rateLimited(let retryAfterSeconds) {
            XCTAssertEqual(retryAfterSeconds, 31)
        } catch {
            XCTFail("Expected rate limit error, got \(error).")
        }
    }

    func testLiveOnsemiProviderFetchesSingleExactMPNProductPage() async throws {
        let productPage = Data("""
        <html><body>
        <h1>Audio Transistors | MJ15003</h1>
        <h2>Bipolar Transistor, NPN, 140 V, 20 A</h2>
        <a href="/download/data-sheet/pdf/mj15003-d.pdf">Datasheet</a>
        <table><tr><td>MJ15003G</td><td>Active</td><td>TO-204-2</td><td>NPN</td><td>20</td><td>140</td><td>250</td></tr></table>
        </body></html>
        """.utf8)
        let transport = MockCatalogHTTPTransport(responses: [productPage])
        let provider = LiveOnsemiCatalogProvider(
            productURLTemplate: "https://www.onsemi.test/products/{base_mpn}",
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

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://www.onsemi.test/products/mj15003")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html,application/xhtml+xml")
        XCTAssertEqual(result.candidates.first?.mpn, "MJ15003G")
        XCTAssertEqual(result.candidates.first?.evidence.first?.cachePolicy, "live_manufacturer_fallback")
        XCTAssertEqual(result.rawResponse, productPage)
    }

    func testLiveOnsemiProviderSurfacesRateLimitWithRetryAfter() async throws {
        let transport = MockCatalogHTTPTransport(responses: [
            .init(data: Data("rate limited".utf8), statusCode: 429, headers: ["Retry-After": "47"]),
        ])
        let provider = LiveOnsemiCatalogProvider(
            productURLTemplate: "https://www.onsemi.test/products/{base_mpn}",
            transport: transport
        )

        do {
            _ = try await provider.searchWithRawResponse(ComponentSearchRequest(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                constraints: ["manufacturer_part_number": "MJ15003G"],
                requiredEvidenceTypes: [],
                preferredVendors: [],
                excludedManufacturers: [],
                lifecyclePolicy: "active"
            ))
            XCTFail("Expected rate limit error.")
        } catch LiveCatalogProviderError.rateLimited(let retryAfterSeconds) {
            XCTAssertEqual(retryAfterSeconds, 47)
        } catch {
            XCTFail("Expected rate limit error, got \(error).")
        }
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

private func rateLimitSearchRequest() -> ComponentSearchRequest {
    ComponentSearchRequest(
        refdes: "R1",
        role: "bias resistor",
        constraints: ["component_category": "resistor", "resistance": "10kOhm"],
        requiredEvidenceTypes: [],
        preferredVendors: [],
        excludedManufacturers: [],
        lifecyclePolicy: "active"
    )
}

private final class MockCatalogHTTPTransport: CatalogHTTPTransport, @unchecked Sendable {
    struct Response: Sendable {
        var data: Data
        var statusCode: Int
        var headers: [String: String]

        init(data: Data, statusCode: Int = 200, headers: [String: String] = [:]) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Data]) {
        self.responses = responses.map { Response(data: $0) }
    }

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? Response(data: Data()) : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (next.data, response)
    }
}

private extension Data {
    var utf8String: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}
