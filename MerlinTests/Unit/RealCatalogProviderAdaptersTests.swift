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
}
