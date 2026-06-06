import XCTest
@testable import Merlin

@MainActor
final class EvidenceGatedComponentSelectionTests: XCTestCase {
    func testRoleOnlyComponentIntentRequiresVendorResolutionWhenNoProviderConfigured() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.requiresVendorResolution])
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testFixtureProviderEvidenceCanSelectComponent() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)
        let catalogURL = try writeCandidates([validCandidate(mpn: "MJ15003G")], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.selected])
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJ15003G")
        XCTAssertEqual(matrix.providers, ["fixture"])
    }

    func testCommodityPassiveVendorProductEvidenceCanSelectWithoutDatasheetURL() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "RPRE1B",
            role: "tone stack lower resistor",
            constraints: [
                "component_category": "resistor",
                "resistance": "100kOhm",
                "package": "through_hole",
            ]
        ), root: root)
        let catalogURL = try writeCandidates([
            ComponentCandidate(
                mpn: "HVR3700001003JR500",
                manufacturer: "Vishay / BC Components",
                normalizedCategory: "metal_film_resistors_through_hole",
                value: "Metal Film Resistors - Through Hole 1/2watt 100Kohms 5%",
                package: "through_hole",
                ratings: ["resistance": "100K", "power_w": "0.5", "package": "through_hole"],
                lifecycleState: "active",
                availabilitySummary: "5000 available",
                datasheets: [],
                evidence: [
                    ComponentEvidence(
                        providerID: "mouser",
                        sourceURL: "https://www.mouser.com/ProductDetail/Vishay-BC-Components/HVR3700001003JR500",
                        localPath: nil,
                        retrievedAt: "2026-06-05T15:02:08Z",
                        cachePolicy: "live_api",
                        sha256: nil,
                        extractedParameters: ["resistance": "100K", "power_w": "0.5", "package": "through_hole"],
                        confidence: 1.0,
                        warnings: []
                    ),
                ],
                footprintCandidates: []
            ),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "HVR3700001003JR500")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.datasheets, [])
    }

    func testPassiveCandidateWithoutRequiredValueEvidenceCannotSelect() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "RMID1",
            role: "mid tone stack resistor",
            constraints: [
                "component_category": "resistor",
                "resistance": "25kOhm",
                "package": "through_hole",
            ]
        ), root: root)
        let catalogURL = try writeCandidates([
            ComponentCandidate(
                mpn: "UXB0207ZFYYYYTCU95",
                manufacturer: "Vishay",
                normalizedCategory: "metal_film_resistors_through_hole",
                value: "Metal Film Resistors - Through Hole",
                package: "through_hole",
                ratings: ["package": "through_hole"],
                lifecycleState: "active",
                availabilitySummary: "available",
                datasheets: [],
                evidence: [
                    ComponentEvidence(
                        providerID: "mouser",
                        sourceURL: "https://www.mouser.com/ProductDetail/Vishay/UXB0207ZFYYYYTCU95",
                        localPath: nil,
                        retrievedAt: "2026-06-05T15:02:07Z",
                        cachePolicy: "live_api",
                        sha256: nil,
                        extractedParameters: ["package": "through_hole"],
                        confidence: 1.0,
                        warnings: []
                    ),
                ],
                footprintCandidates: []
            ),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testConnectorSubtypeIncompatibleCandidatesBlockSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "JIN",
            role: "high impedance guitar input connector",
            constraints: [
                "component_category": "phone_audio_jack",
                "kind": "connector",
                "positions": "2",
                "mounting": "panel_mount",
            ]
        ), root: root)
        var freeHangingHousing = validCandidate(mpn: "1-2232892-2", category: "free_hanging_panel_mount")
        freeHangingHousing.value = "2P MONOPLUG 2.5"
        freeHangingHousing.package = "Free Hanging (In-Line)"
        freeHangingHousing.ratings = ["positions": "2", "package": "Free Hanging (In-Line)"]
        var dcPowerJack = validCandidate(mpn: "PJ-110AH", category: "dc_power_connectors")
        dcPowerJack.value = "DC Power Connectors 2.0 x 6.0 mm vertical through hole DC Power Jack"
        dcPowerJack.package = "through_hole"
        dcPowerJack.ratings = ["positions": "2", "package": "through_hole"]
        var terminalHeader = validCandidate(mpn: "31017102", category: "headers_plugs_and_sockets")
        terminalHeader.value = "TERM BLOCK HDR 2POS 5MM"
        terminalHeader.package = "Through Hole"
        terminalHeader.ratings = ["positions": "2", "package": "Through Hole"]
        terminalHeader.availabilitySummary = "14526 available"
        let catalogURL = try writeCandidates([freeHangingHousing, dcPowerJack, terminalHeader], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testPanelMountAudioJackUsesConnectorMountingAsPackageEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "JIN",
            role: "high impedance guitar input connector",
            constraints: [
                "component_category": "phone_audio_jack",
                "kind": "connector",
                "positions": "2",
                "mounting": "panel_mount",
            ]
        ), root: root)
        let switchcraft = ComponentCandidate(
            mpn: "174S",
            manufacturer: "Switchcraft",
            normalizedCategory: "phone_connectors",
            value: "Phone Connectors 2 COND 1/4\" SHIELDED",
            package: "",
            ratings: ["positions": "2", "standard_pack_qty": "100"],
            lifecycleState: "active",
            availabilitySummary: "38 In Stock",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: "Switchcraft",
                    mpn: "174S",
                    url: "https://www.mouser.com/datasheet/3/144/1/174S_CD.pdf",
                    localPath: nil,
                    sha256: nil,
                    providerID: "mouser",
                    retrievedAt: "2026-06-04T17:38:11Z",
                    license: "live_api",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "mouser",
                    sourceURL: "https://www.mouser.com/ProductDetail/Switchcraft/174S",
                    localPath: nil,
                    retrievedAt: "2026-06-04T17:38:11Z",
                    cachePolicy: "live_api",
                    sha256: nil,
                    extractedParameters: ["positions": "2", "standard_pack_qty": "100"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
        let catalogURL = try writeCandidates([switchcraft], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "174S")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.package, "panel_mount")
    }

    func testMultipleValidCandidatesSelectStableCandidateWhenScoresTie() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "BR1", role: "bridge rectifier"), root: root)
        let catalogURL = try writeCandidates([
            validCandidate(mpn: "GBU806", category: "bridge_rectifier"),
            validCandidate(mpn: "GBU808", category: "bridge_rectifier"),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.selected])
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "GBU806")
        XCTAssertEqual(matrix.decisions.first?.candidateSet.count, 2)
        XCTAssertTrue(matrix.decisions.first?.rationale.contains("stable catalog candidate") == true)
    }

    func testMultipleValidCandidatesSelectsUniqueBestRankedCandidate() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "BR1",
            role: "bridge rectifier",
            constraints: [
                "component_category": "bridge_rectifier",
                "mounting": "through_hole",
                "voltage_rating": "100V",
                "current_rating": "8A",
            ]
        ), root: root)
        var weaker = validCandidate(mpn: "GBU406", category: "bridge_rectifiers")
        weaker.package = "SMD"
        weaker.ratings = ["voltage_v": "50", "current_a": "4"]
        weaker.lifecycleState = "Obsolete"
        weaker.availabilitySummary = "0 In Stock"
        var preferred = validCandidate(mpn: "GBU810-G", category: "bridge_rectifiers")
        preferred.manufacturer = "Comchip Technology"
        preferred.package = "through_hole"
        preferred.ratings = ["voltage_v": "100", "current_a": "8", "mounting_type": "Through Hole"]
        preferred.lifecycleState = "Active"
        preferred.availabilitySummary = "27 In Stock"
        let catalogURL = try writeCandidates([weaker, preferred], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "GBU810-G")
        XCTAssertEqual(matrix.decisions.first?.candidateSet.map(\.mpn), ["GBU810-G"])
    }

    func testCandidateEvidenceHydrationPreventsFalsePackageDatasheetBlock() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "BR1", role: "bridge rectifier"), root: root)
        let candidate = ComponentCandidate(
            mpn: "GBU810-G",
            manufacturer: "Comchip Technology",
            normalizedCategory: "bridge_rectifiers",
            value: nil,
            package: "",
            ratings: [:],
            lifecycleState: "Active",
            availabilitySummary: "27 In Stock",
            datasheets: [],
            evidence: [
                ComponentEvidence(
                    providerID: "mouser",
                    sourceURL: "https://example.invalid/GBU810-G",
                    localPath: nil,
                    retrievedAt: "2026-06-02T00:00:00Z",
                    cachePolicy: "fixture",
                    sha256: nil,
                    extractedParameters: [
                        "target_refdes": "BR1",
                        "package_case": "GBU",
                        "mounting_type": "Through Hole",
                        "voltage_v": "100",
                        "current_a": "8",
                        "datasheet_url": "https://example.invalid/GBU810-G.pdf",
                    ],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
        let catalogURL = try writeCandidates([candidate], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        let selected = try XCTUnwrap(matrix.decisions.first?.selectedCandidate)
        XCTAssertEqual(selected.package, "GBU")
        XCTAssertEqual(selected.ratings["voltage_v"], "100")
        XCTAssertEqual(selected.datasheets.first?.url, "https://example.invalid/GBU810-G.pdf")
    }

    func testSamePartProviderEvidenceHydratesBeforeValidation() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "BR1",
            role: "bridge rectifier",
            constraints: [
                "component_category": "bridge_rectifier",
                "voltage_rating": "100V",
                "current_rating": "8A",
                "mounting": "through_hole",
            ]
        ), root: root)
        var mouserSearch = catalogCandidate(
            refdes: "BR1",
            mpn: "GBU810-G",
            category: "bridge_rectifiers",
            value: "Bridge Rectifiers 100 Volt 8.0 Amp Glass Passivated GBU Through Hole",
            package: "GBU",
            ratings: ["voltage_v": "100", "current_a": "8", "mounting_type": "Through Hole"]
        )
        mouserSearch.datasheets = []
        mouserSearch.evidence = mouserSearch.evidence.map { evidence in
            var evidence = evidence
            evidence.providerID = "mouser"
            evidence.sourceURL = "https://mouser.example/GBU810-G"
            return evidence
        }
        var nexarDetail = catalogCandidate(
            refdes: "BR1",
            mpn: "GBU810-G",
            manufacturer: "Comchip Technology",
            category: "bridge_rectifiers",
            value: "GBU810-G bridge rectifier",
            package: "",
            ratings: ["datasheet_url": "https://example.invalid/GBU810-G.pdf"]
        )
        nexarDetail.datasheets = [
            DatasheetEvidence(
                manufacturer: "Comchip Technology",
                mpn: "GBU810-G",
                url: "https://example.invalid/GBU810-G.pdf",
                localPath: nil,
                sha256: nil,
                providerID: "nexar",
                retrievedAt: "2026-06-02T12:00:00Z",
                license: "fixture",
                citations: []
            ),
        ]
        nexarDetail.evidence = nexarDetail.evidence.map { evidence in
            var evidence = evidence
            evidence.providerID = "nexar"
            evidence.sourceURL = "https://octopart.example/GBU810-G"
            return evidence
        }
        let catalogURL = try writeCandidates([mouserSearch, nexarDetail], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        let selected = try XCTUnwrap(matrix.decisions.first?.selectedCandidate)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(selected.mpn, "GBU810-G")
        XCTAssertEqual(selected.package, "GBU")
        XCTAssertEqual(selected.ratings["current_a"], "8")
        XCTAssertEqual(selected.datasheets.first?.url, "https://example.invalid/GBU810-G.pdf")
        XCTAssertEqual(Set(selected.evidence.map(\.providerID)), Set(["mouser", "nexar"]))
    }

    func testExplicitPackageConstraintRejectsIncompatibleCatalogCandidate() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(
            refdes: "QPRE1",
            role: "low-noise small-signal preamp transistor stage",
            constraints: [
                "component_category": "low_noise_transistor",
                "device_family": "JFET_or_low_noise_BJT",
                "package": "TO-92",
            ]
        ), root: root)
        var candidate = validCandidate(mpn: "ULN2003AT16-13", category: "darlington_transistors")
        candidate.manufacturer = "Diodes Incorporated"
        candidate.package = "TSSOP-16"
        candidate.ratings = ["package": "TSSOP-16"]
        candidate.lifecycleState = "New Product"
        candidate.availabilitySummary = "2061 In Stock"
        let catalogURL = try writeCandidates([candidate], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertNotEqual(matrix.decisions.first?.status, .selected)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testMouserAdapterExtractsPackageAndRatingsFromDescription() throws {
        let data = Data("""
        {"SearchResults":{"Parts":[{
          "Manufacturer":"Comchip Technology",
          "ManufacturerPartNumber":"GBU810-G",
          "Description":"Bridge Rectifiers 100 Volt 8.0 Amp Glass Passivated GBU Through Hole",
          "Category":"Bridge Rectifiers",
          "DataSheetUrl":"https://example.invalid/GBU810-G.pdf",
          "ProductDetailUrl":"https://mouser.example/GBU810-G",
          "LifecycleStatus":"Active",
          "Availability":"27 In Stock",
          "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Tube"}]
        }]}}
        """.utf8)

        let candidate = try XCTUnwrap(MouserCatalogProviderAdapter().mapRecordedResponse(data).first)

        XCTAssertEqual(candidate.package, "GBU")
        XCTAssertEqual(candidate.ratings["voltage_v"], "100")
        XCTAssertEqual(candidate.ratings["current_a"], "8.0")
        XCTAssertFalse(candidate.datasheets.isEmpty)
    }

    func testDigiKeyAdapterPreservesDatasheetPackageStockAndRatings() throws {
        let data = Data("""
        {"Products":[{
          "Manufacturer":{"Name":"YAGEO"},
          "ManufacturerProductNumber":"MFR-25FBF52-10K",
          "ProductDescription":"RES 10K OHM 1% 1/4W AXIAL",
          "Description":{"DetailedDescription":"10 kOhms ±1% 0.25W Through Hole Axial Resistor"},
          "Category":{"Name":"Through Hole Resistors"},
          "DatasheetUrl":"https://example.invalid/MFR-25FBF52-10K.pdf",
          "ProductUrl":"https://digikey.example/MFR-25FBF52-10K",
          "ProductStatus":"Active",
          "QuantityAvailable":12345,
          "Parameters":[
            {"ParameterText":"Resistance","ValueText":"10 kOhms"},
            {"ParameterText":"Power (Watts)","ValueText":"0.25W"},
            {"ParameterText":"Tolerance","ValueText":"±1%"},
            {"ParameterText":"Package / Case","ValueText":"Axial"}
          ]
        }]}
        """.utf8)

        let candidate = try XCTUnwrap(DigiKeyCatalogProviderAdapter().mapRecordedResponse(data).first)

        XCTAssertEqual(candidate.mpn, "MFR-25FBF52-10K")
        XCTAssertEqual(candidate.manufacturer, "YAGEO")
        XCTAssertEqual(candidate.package, "Axial")
        XCTAssertEqual(candidate.availabilitySummary, "12345 available")
        XCTAssertEqual(candidate.lifecycleState, "Active")
        XCTAssertEqual(candidate.datasheets.first?.url, "https://example.invalid/MFR-25FBF52-10K.pdf")
        XCTAssertEqual(candidate.ratings["resistance"], "10 kOhms")
        XCTAssertEqual(candidate.ratings["power_watts"], "0.25W")
        XCTAssertEqual(candidate.evidence.first?.sourceURL, "https://digikey.example/MFR-25FBF52-10K")
    }

    func testMouserNonResistorAdapterExtractsPackageAndDatasheetEvidence() throws {
        let data = Data("""
        {"SearchResults":{"Parts":[
          {
            "Manufacturer":"Comchip Technology",
            "ManufacturerPartNumber":"GBU810-G",
            "Description":"Bridge Rectifiers 100 Volt 8.0 Amp Glass Passivated GBU Through Hole",
            "Category":"Bridge Rectifiers",
            "DataSheetUrl":"https://example.invalid/GBU810-G.pdf",
            "ProductDetailUrl":"https://mouser.example/GBU810-G",
            "LifecycleStatus":"Active",
            "Availability":"27 In Stock",
            "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Tube"}]
          },
          {
            "Manufacturer":"KEMET",
            "ManufacturerPartNumber":"SMR5104J50J01L4BULK",
            "Description":"Film Capacitors 50volts 0.10uF 5% LS 5mm Radial",
            "Category":"Film Capacitors",
            "DataSheetUrl":"https://example.invalid/SMR5104.pdf",
            "ProductDetailUrl":"https://mouser.example/SMR5104",
            "LifecycleStatus":"Active",
            "Availability":"2000 In Stock",
            "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Bulk"}]
          },
          {
            "Manufacturer":"Same Sky",
            "ManufacturerPartNumber":"TBP06H-500-02BK",
            "Description":"Pluggable Terminal Blocks Terminal Block Header, Male Pins, Unshrouded, 2 pin, 5.0mm, Vertical Through Hole",
            "Category":"Pluggable Terminal Blocks",
            "DataSheetUrl":"https://example.invalid/TBP06H.pdf",
            "ProductDetailUrl":"https://mouser.example/TBP06H",
            "LifecycleStatus":"New Product",
            "Availability":"5999 In Stock",
            "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Bulk"}]
          },
          {
            "Manufacturer":"Microchip / Microsemi",
            "ManufacturerPartNumber":"2N3421",
            "Description":"Bipolar Transistors - BJT 80V 3A 1W NPN Power BJT TO-126 THT",
            "Category":"Bipolar Transistors - BJT",
            "DataSheetUrl":"https://example.invalid/2N3421.pdf",
            "ProductDetailUrl":"https://mouser.example/2N3421",
            "LifecycleStatus":"Active",
            "Availability":"473 In Stock",
            "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Bulk"}]
          },
          {
            "Manufacturer":"Amphenol Piher",
            "ManufacturerPartNumber":"PT15GV15-104A2020-E-PF-S",
            "Description":"Trimmer Resistors - Through Hole 100K ohm linear taper",
            "Category":"Trimmer Resistors - Through Hole",
            "DataSheetUrl":"https://example.invalid/PT15.pdf",
            "ProductDetailUrl":"https://mouser.example/PT15",
            "LifecycleStatus":"Active",
            "Availability":"400 In Stock",
            "ProductAttributes":[{"AttributeName":"Packaging","AttributeValue":"Bulk"}]
          }
        ]}}
        """.utf8)

        let candidates = try MouserCatalogProviderAdapter().mapRecordedResponse(data)
        let byMPN = Dictionary(uniqueKeysWithValues: candidates.map { ($0.mpn, $0) })

        let bridge = try XCTUnwrap(byMPN["GBU810-G"])
        XCTAssertEqual(bridge.package, "GBU")
        XCTAssertEqual(bridge.ratings["voltage_v"], "100")
        XCTAssertEqual(bridge.ratings["current_a"], "8.0")
        XCTAssertEqual(bridge.datasheets.first?.url, "https://example.invalid/GBU810-G.pdf")

        let capacitor = try XCTUnwrap(byMPN["SMR5104J50J01L4BULK"])
        XCTAssertEqual(capacitor.package, "Radial")
        XCTAssertEqual(capacitor.ratings["capacitance"], "0.10uF")
        XCTAssertEqual(capacitor.ratings["voltage_v"], "50")
        XCTAssertEqual(capacitor.datasheets.first?.url, "https://example.invalid/SMR5104.pdf")

        let connector = try XCTUnwrap(byMPN["TBP06H-500-02BK"])
        XCTAssertEqual(connector.package, "through_hole")
        XCTAssertEqual(connector.ratings["positions"], "2")
        XCTAssertEqual(connector.datasheets.first?.url, "https://example.invalid/TBP06H.pdf")

        let transistor = try XCTUnwrap(byMPN["2N3421"])
        XCTAssertEqual(transistor.package, "TO-126")
        XCTAssertEqual(transistor.ratings["polarity"], "NPN")
        XCTAssertEqual(transistor.ratings["voltage_v"], "80")
        XCTAssertEqual(transistor.ratings["current_a"], "3")
        XCTAssertEqual(transistor.ratings["power_w"], "1")
        XCTAssertEqual(transistor.datasheets.first?.url, "https://example.invalid/2N3421.pdf")

        let potentiometer = try XCTUnwrap(byMPN["PT15GV15-104A2020-E-PF-S"])
        XCTAssertEqual(potentiometer.package, "through_hole")
        XCTAssertEqual(potentiometer.ratings["resistance"], "100K")
        XCTAssertEqual(potentiometer.ratings["taper"], "linear")
        XCTAssertEqual(potentiometer.datasheets.first?.url, "https://example.invalid/PT15.pdf")
    }

    func testDigiKeyNonResistorAdapterExtractsPackageAndDatasheetEvidence() throws {
        let data = Data("""
        {"Products":[{
          "Manufacturer":{"Name":"KEMET"},
          "ManufacturerProductNumber":"PHE426MJ5470JR05",
          "Description":{"ProductDescription":"47NF63 5%V","DetailedDescription":"0.047 µF Film Capacitor 250V 630V Polypropylene (PP), Metallized Radial"},
          "Category":{"Name":"Capacitors","ChildCategories":[{"Name":"Film Capacitors","ChildCategories":[]}]},
          "DatasheetUrl":"https://example.invalid/PHE426.pdf",
          "ProductUrl":"https://digikey.example/PHE426",
          "ProductStatus":"Active",
          "QuantityAvailable":42,
          "Parameters":[
            {"ParameterText":"Capacitance","ValueText":"0.047 µF"},
            {"ParameterText":"Voltage Rating - DC","ValueText":"630V"},
            {"ParameterText":"Package / Case","ValueText":"Radial"},
            {"ParameterText":"Mounting Type","ValueText":"Through Hole"}
          ]
        },{
          "Manufacturer":{"Name":"Microchip / Microsemi"},
          "ManufacturerProductNumber":"2N3421",
          "Description":{"DetailedDescription":"NPN Bipolar Transistor 80V 3A 1W TO-126 Through Hole"},
          "Category":{"Name":"Discrete Semiconductor Products","ChildCategories":[{"Name":"Bipolar Transistors - BJT","ChildCategories":[]}]},
          "DatasheetUrl":"https://example.invalid/2N3421.pdf",
          "ProductUrl":"https://digikey.example/2N3421",
          "ProductStatus":"Active",
          "QuantityAvailable":7,
          "Parameters":[
            {"ParameterText":"Transistor Polarity","ValueText":"NPN"},
            {"ParameterText":"Voltage - Collector Emitter Breakdown (Max)","ValueText":"80V"},
            {"ParameterText":"Current - Collector (Ic) (Max)","ValueText":"3A"},
            {"ParameterText":"Power - Max","ValueText":"1W"},
            {"ParameterText":"Package / Case","ValueText":"TO-126"}
          ]
        }]}
        """.utf8)

        let candidates = try DigiKeyCatalogProviderAdapter().mapRecordedResponse(data)
        let byMPN = Dictionary(uniqueKeysWithValues: candidates.map { ($0.mpn, $0) })

        let capacitor = try XCTUnwrap(byMPN["PHE426MJ5470JR05"])
        XCTAssertEqual(capacitor.package, "Radial")
        XCTAssertEqual(capacitor.ratings["capacitance"], "0.047 µF")
        XCTAssertEqual(capacitor.ratings["voltage_rating_dc"], "630V")
        XCTAssertEqual(capacitor.datasheets.first?.url, "https://example.invalid/PHE426.pdf")
        XCTAssertEqual(capacitor.evidence.first?.sourceURL, "https://digikey.example/PHE426")

        let transistor = try XCTUnwrap(byMPN["2N3421"])
        XCTAssertEqual(transistor.package, "TO-126")
        XCTAssertEqual(transistor.ratings["polarity"], "NPN")
        XCTAssertEqual(transistor.ratings["voltage_v"], "80")
        XCTAssertEqual(transistor.ratings["current_a"], "3")
        XCTAssertEqual(transistor.ratings["power_w"], "1")
        XCTAssertEqual(transistor.datasheets.first?.url, "https://example.invalid/2N3421.pdf")
        XCTAssertEqual(transistor.evidence.first?.sourceURL, "https://digikey.example/2N3421")
    }

    func testResistorRoleQueriesUseStructuredElectricalIntent() throws {
        let preampRequest = ComponentSearchRequest(
            refdes: "RPRE1",
            role: "preamp collector load resistor",
            constraints: [
                "selected_symbol": "Device:R",
                "resistance": "10 kOhm",
                "power_rating": "0.25W",
                "tolerance": "1%",
                "selected_footprint": "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal",
            ],
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: ["digikey", "mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        )
        let biasRequest = ComponentSearchRequest(
            refdes: "RBIAS1",
            role: "output stage bias resistor",
            constraints: [
                "selected_symbol": "Device:R",
                "resistance": "0.47 ohm",
                "power_rating": "5W",
                "tolerance": "5%",
                "mounting": "through_hole",
            ],
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: ["digikey", "mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        )

        let builder = CatalogSearchQueryBuilder()
        let preampQuery = builder.keyword(for: preampRequest)
        let biasQuery = builder.keyword(for: biasRequest)

        XCTAssertTrue(preampQuery.lowercased().contains("resistor"))
        XCTAssertTrue(preampQuery.contains("10 kOhm"))
        XCTAssertTrue(preampQuery.contains("0.25W"))
        XCTAssertFalse(preampQuery.contains("Device:R"))
        XCTAssertTrue(biasQuery.lowercased().contains("resistor"))
        XCTAssertTrue(biasQuery.contains("0.47 ohm"))
        XCTAssertTrue(biasQuery.contains("5W"))
        XCTAssertTrue(biasQuery.lowercased().contains("through hole"))
        XCTAssertFalse(biasQuery.contains("Device:R"))
    }

    func testNonResistorQueriesUseStructuredElectricalIntent() throws {
        let builder = CatalogSearchQueryBuilder()
        let requests = [
            ComponentSearchRequest(
                refdes: "BR1",
                role: "bridge rectifier for isolated secondary supply",
                constraints: [
                    "component_category": "bridge_rectifier",
                    "voltage_rating": "100V",
                    "current_rating": "8A",
                    "selected_symbol": "Device:Bridge_Rectifier",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
            ComponentSearchRequest(
                refdes: "CBASS1",
                role: "bass tone capacitor",
                constraints: [
                    "component_category": "film_or_c0g_capacitor",
                    "capacitance": "100nF",
                    "voltage_rating": "50V",
                    "dielectric": "film",
                    "selected_symbol": "Device:C",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
            ComponentSearchRequest(
                refdes: "QDRV1",
                role: "Class-A output driver transistor",
                constraints: [
                    "component_category": "driver_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "80V",
                    "current_rating": "1A",
                    "package": "TO-126_or_TO-220",
                    "selected_symbol": "Device:Q_NPN_BCE",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
            ComponentSearchRequest(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                constraints: [
                    "component_category": "power_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "80V",
                    "current_rating": "8A",
                    "power_rating": "100W",
                    "package": "TO-3_or_TO-247",
                    "selected_symbol": "Device:Q_NPN_BCE",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
            ComponentSearchRequest(
                refdes: "JSEC",
                role: "isolated transformer secondary connector",
                constraints: [
                    "component_category": "terminal_block",
                    "positions": "2",
                    "current_rating": "10A",
                    "voltage_rating": "300V",
                    "selected_symbol": "Connector_Generic:Conn_01x02",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
            ComponentSearchRequest(
                refdes: "RVFILT1",
                role: "sweepable filter frequency control potentiometer",
                constraints: [
                    "component_category": "potentiometer",
                    "resistance": "100kOhm",
                    "taper": "linear",
                    "selected_symbol": "Device:R_POT",
                ],
                requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
                preferredVendors: ["digikey", "mouser"],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_ltb"
            ),
        ]

        let queries = requests.map { builder.keyword(for: $0) }

        XCTAssertTrue(queries[0].lowercased().contains("bridge rectifier"))
        XCTAssertTrue(queries[0].contains("100V"))
        XCTAssertTrue(queries[0].contains("8A"))
        XCTAssertFalse(queries[0].contains("Device:Bridge_Rectifier"))
        XCTAssertTrue(queries[1].lowercased().contains("capacitor"))
        XCTAssertTrue(queries[1].contains("100nF"))
        XCTAssertTrue(queries[1].lowercased().contains("film"))
        XCTAssertFalse(queries[1].contains("Device:C"))
        XCTAssertTrue(queries[2].lowercased().contains("npn power transistor"))
        XCTAssertTrue(queries[2].contains("80V"))
        XCTAssertTrue(queries[2].contains("1A"))
        XCTAssertTrue(queries[2].contains("TO-126"))
        XCTAssertTrue(queries[2].contains("TO-220"))
        XCTAssertFalse(queries[2].contains("Device:Q_NPN_BCE"))
        XCTAssertTrue(queries[3].lowercased().contains("npn power transistor"))
        XCTAssertTrue(queries[3].contains("100W"))
        XCTAssertTrue(queries[3].contains("8A"))
        XCTAssertTrue(queries[3].contains("TO-3"))
        XCTAssertTrue(queries[3].contains("TO-247"))
        XCTAssertFalse(queries[3].contains("Device:Q_NPN_BCE"))
        XCTAssertTrue(queries[4].lowercased().contains("2 position connector"))
        XCTAssertTrue(queries[4].contains("10A"))
        XCTAssertFalse(queries[4].contains("Connector_Generic"))
        XCTAssertTrue(queries[5].lowercased().contains("potentiometer"))
        XCTAssertTrue(queries[5].contains("100kOhm"))
        XCTAssertTrue(queries[5].lowercased().contains("linear"))
        XCTAssertFalse(queries[5].contains("Device:R_POT"))

        let driverFallbacks = builder.keywords(for: requests[2])
        XCTAssertTrue(driverFallbacks.contains { $0 == "NPN medium power transistor" }, driverFallbacks.joined(separator: " | "))
        XCTAssertTrue(driverFallbacks.contains { $0 == "NPN transistor 80V 1A" }, driverFallbacks.joined(separator: " | "))
        XCTAssertTrue(driverFallbacks.contains { $0 == "NPN medium power transistor TO-220" }, driverFallbacks.joined(separator: " | "))

        let outputFallbacks = builder.keywords(for: requests[3])
        XCTAssertTrue(outputFallbacks.contains { $0 == "NPN power transistor" }, outputFallbacks.joined(separator: " | "))
        XCTAssertTrue(outputFallbacks.contains { $0 == "NPN power transistor 100W" }, outputFallbacks.joined(separator: " | "))
        XCTAssertTrue(outputFallbacks.contains { $0 == "NPN power transistor TO-247" }, outputFallbacks.joined(separator: " | "))
    }

    func testCapacitorSelectionUsesValueVoltageAndDielectricEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "TONE1", role: "tone circuit"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "CBASS1",
                role: "bass tone capacitor",
                selectedSymbol: "Device:C",
                pins: ["1", "2"],
                constraints: [
                    "component_category": "film_capacitor",
                    "capacitance": "100nF",
                    "voltage_rating": "50V",
                    "dielectric": "film",
                    "mounting": "through_hole",
                ]
            ),
        ], root: root)
        let wrongValue = catalogCandidate(
            refdes: "CBASS1",
            mpn: "DME2S22K-F",
            category: "film_capacitors",
            value: "Film Capacitors DME 250V 0.022uF",
            package: "Radial",
            ratings: ["capacitance": "0.022uF", "voltage_v": "250", "dielectric_material": "Polyester Film", "mounting_type": "Through Hole"]
        )
        let preferred = catalogCandidate(
            refdes: "CBASS1",
            mpn: "SMR5104J50J01L4BULK",
            category: "film_capacitors",
            value: "Film Capacitors 50volts 0.10uF 5% LS 5mm",
            package: "Radial",
            ratings: ["capacitance": "0.10uF", "voltage_v": "50", "dielectric_material": "Polyester Film", "mounting_type": "Through Hole"]
        )
        let catalogURL = try writeCandidates([wrongValue, preferred], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "SMR5104J50J01L4BULK")
    }

    func testDeterministicRankingPrefersExactRatingsOverOverspecifiedValidCandidates() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "TONE1", role: "tone circuit"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "CBASS1",
                role: "bass tone capacitor",
                selectedSymbol: "Device:C",
                pins: ["1", "2"],
                constraints: [
                    "component_category": "film_capacitor",
                    "capacitance": "100nF",
                    "voltage_rating": "50V",
                    "dielectric": "film",
                    "mounting": "through_hole",
                ]
            ),
        ], root: root)
        let oversized = catalogCandidate(
            refdes: "CBASS1",
            mpn: "PHE426DJ6100JR06",
            category: "film_capacitors",
            value: "Film Capacitor 0.10uF 250V Radial Through Hole",
            package: "Radial",
            ratings: ["capacitance": "0.10uF", "voltage_v": "250", "dielectric_material": "Polyester Film", "mounting_type": "Through Hole"]
        )
        let exact = catalogCandidate(
            refdes: "CBASS1",
            mpn: "SMR5104J50J01L4BULK",
            category: "film_capacitors",
            value: "Film Capacitor 0.10uF 50V Radial Through Hole",
            package: "Radial",
            ratings: ["capacitance": "0.10uF", "voltage_v": "50", "dielectric_material": "Polyester Film", "mounting_type": "Through Hole"]
        )
        let catalogURL = try writeCandidates([oversized, exact], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "SMR5104J50J01L4BULK")
    }

    func testSemiconductorSelectionUsesPolarityAndRatingsEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QDRV1", role: "voltage driver"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "QDRV1",
                role: "Class-A output driver transistor",
                selectedSymbol: "Device:Q_NPN_BCE",
                pins: ["B", "C", "E"],
                constraints: [
                    "component_category": "driver_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "80V",
                    "current_rating": "1A",
                    "power_rating": "1W",
                    "package": "TO-126_or_TO-220",
                ]
            ),
        ], root: root)
        let wrongPolarity = catalogCandidate(
            refdes: "QDRV1",
            mpn: "MJE350G",
            category: "bipolar_transistors_bjt",
            value: "Bipolar Transistors - BJT PNP 300V 0.5A TO-126",
            package: "TO-126",
            ratings: ["polarity": "PNP", "voltage_v": "300", "current_a": "0.5", "power_w": "4"]
        )
        let preferred = catalogCandidate(
            refdes: "QDRV1",
            mpn: "MJE340G",
            category: "bipolar_transistors_bjt",
            value: "Bipolar Transistors - BJT NPN 300V 0.5A TO-126",
            package: "TO-126",
            ratings: ["polarity": "NPN", "voltage_v": "300", "current_a": "1", "power_w": "4"]
        )
        let catalogURL = try writeCandidates([wrongPolarity, preferred], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJE340G")
    }

    func testConnectorSelectionUsesPositionAndRatingEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "JSEC", role: "secondary connector"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "JSEC",
                role: "isolated transformer secondary connector",
                selectedSymbol: "Connector_Generic:Conn_01x02",
                pins: ["1", "2"],
                constraints: [
                    "component_category": "terminal_block",
                    "positions": "2",
                    "current_rating": "10A",
                    "voltage_rating": "300V",
                    "mounting": "through_hole",
                ]
            ),
        ], root: root)
        let wrongPositions = catalogCandidate(
            refdes: "JSEC",
            mpn: "TBP06H-500-03BK",
            category: "pluggable_terminal_blocks",
            value: "Terminal Block Header 3 pin 5.0mm Vertical Through Hole",
            package: "through_hole",
            ratings: ["positions": "3", "current_a": "16", "voltage_v": "300", "mounting_type": "Through Hole"]
        )
        let preferred = catalogCandidate(
            refdes: "JSEC",
            mpn: "TBP06H-500-02BK",
            category: "pluggable_terminal_blocks",
            value: "Terminal Block Header 2 pin 5.0mm Vertical Through Hole",
            package: "through_hole",
            ratings: ["positions": "2", "current_a": "16", "voltage_v": "300", "mounting_type": "Through Hole"]
        )
        let catalogURL = try writeCandidates([wrongPositions, preferred], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "TBP06H-500-02BK")
    }

    func testCategoryIncompatibleTargetedCandidateBlocksConnectorSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "JSEC", role: "secondary connector"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "JSEC",
                role: "isolated transformer secondary connector",
                selectedSymbol: "Connector_Generic:Conn_01x02",
                pins: ["1", "2"],
                constraints: [
                    "component_category": "terminal_block",
                    "positions": "2",
                    "current_rating": "10A",
                    "voltage_rating": "300V",
                    "mounting": "through_hole",
                ]
            ),
        ], root: root)
        let screwTerminalCapacitor = catalogCandidate(
            refdes: "JSEC",
            mpn: "CGS801T450V4L",
            manufacturer: "Knowles / Illinois Capacitor",
            category: "aluminum_electrolytic_capacitors_screw_terminal",
            value: "Aluminum Electrolytic Capacitors - Screw Terminal LYTIC 450V 800uF",
            package: "screw_terminal",
            ratings: ["capacitance": "800uF", "voltage_v": "450", "package": "screw_terminal"]
        )
        let catalogURL = try writeCandidates([screwTerminalCapacitor], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testPotentiometerSelectionUsesResistanceAndTaperEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RVFILT1",
                role: "sweepable filter frequency control potentiometer",
                selectedSymbol: "Device:R_POT",
                pins: ["1", "2", "3"],
                constraints: [
                    "component_category": "potentiometer",
                    "resistance": "100kOhm",
                    "taper": "linear",
                    "mounting": "through_hole",
                ]
            ),
        ], root: root)
        let wrongTaper = catalogCandidate(
            refdes: "RVFILT1",
            mpn: "PT15GV15-104B2020",
            category: "trimmer_resistors_through_hole",
            value: "Trimmer Resistors Through Hole 100K audio taper",
            package: "through_hole",
            ratings: ["resistance": "100K", "taper": "audio", "mounting_type": "Through Hole"]
        )
        let preferred = catalogCandidate(
            refdes: "RVFILT1",
            mpn: "PT15GV15-104A2020",
            category: "trimmer_resistors_through_hole",
            value: "Trimmer Resistors Through Hole 100K linear taper",
            package: "through_hole",
            ratings: ["resistance": "100K", "taper": "linear", "mounting_type": "Through Hole"]
        )
        let catalogURL = try writeCandidates([wrongTaper, preferred], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "PT15GV15-104A2020")
    }

    func testIncompleteProviderCandidateBlocksSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)
        let catalogURL = try writeCandidates([
            ComponentCandidate(
                mpn: "UNKNOWN",
                manufacturer: "",
                normalizedCategory: "power_transistor",
                value: nil,
                package: "",
                ratings: [:],
                lifecycleState: "",
                availabilitySummary: "",
                datasheets: [],
                evidence: [],
                footprintCandidates: []
            ),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "COMPONENT_SELECTION_BLOCKED" })
        let matrixArtifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        let matrix = try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: matrixArtifact.url))
        XCTAssertEqual(matrix.decisions.map(\.status), [.blocked])
    }

    func testCircuitIRComponentsDriveSelectionInsteadOfBlockIntent() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
            circuitComponent(refdes: "CFILT1", role: "sweepable boost/cut capacitor", selectedSymbol: "Device:C", pins: ["1", "2"]),
        ], root: root)
        let catalogURL = try writeCandidates([
            validCandidate(mpn: "RC0603FR-0710KL", category: "resistor"),
            validCandidate(mpn: "C0603C473K5RACTU", category: "capacitor"),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        let decisions = Dictionary(uniqueKeysWithValues: matrix.decisions.map { ($0.refdes, $0) })
        XCTAssertEqual(Set(decisions.keys), ["RFILT1", "CFILT1"])
        XCTAssertEqual(decisions["RFILT1"]?.status, .selected)
        XCTAssertEqual(decisions["RFILT1"]?.selectedCandidate?.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(decisions["CFILT1"]?.status, .selected)
        XCTAssertEqual(decisions["CFILT1"]?.selectedCandidate?.mpn, "C0603C473K5RACTU")
        XCTAssertNil(decisions["FILTER1"])
    }

    func testCircuitIRComponentsRequireVendorResolutionWhenNoCatalogEvidenceExists() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
            circuitComponent(refdes: "CFILT1", role: "sweepable boost/cut capacitor", selectedSymbol: "Device:C", pins: ["1", "2"]),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.refdes), ["RFILT1", "CFILT1"])
        XCTAssertEqual(matrix.decisions.map(\.status), [.requiresVendorResolution, .requiresVendorResolution])
    }

    func testRuntimeCatalogProviderFixtureDrivesCircuitIRSelectionWithoutCandidateFile() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"mouser":"\#(mouserURL.path)"}}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.providers, ["mouser"])
        XCTAssertEqual(matrix.cacheMetadata["source"], "runtime_catalog_providers")
        XCTAssertEqual(matrix.cacheMetadata["ttl_seconds"], "86400")
        XCTAssertEqual(matrix.decisions.map(\.refdes), ["RFILT1"])
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.evidence.first?.providerID, "mouser")
    }

    func testNexarProviderFixtureUsesNexarAdapterForSelectionEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "OUTPUT1", role: "output stage"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                selectedSymbol: "Device:Q_NPN_BCE",
                pins: ["B", "C", "E"],
                constraints: [
                    "component_category": "power_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "120V",
                    "current_rating": "10A",
                    "power_rating": "150W",
                    "package": "TO-3",
                ]
            ),
        ], root: root)
        let nexarURL = try writeNexarFixture(root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"nexar":"\#(nexarURL.path)"}}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.providers, ["nexar"])
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJ15003G")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.datasheets.first?.providerID, "nexar")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.evidence.first?.providerID, "nexar")
    }

    func testVendorFeedPathProvidesLocalCatalogEvidenceForSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "OUTPUT1", role: "output stage"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                selectedSymbol: "Device:Q_NPN_BCE",
                pins: ["B", "C", "E"],
                constraints: [
                    "component_category": "power_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "120V",
                    "current_rating": "10A",
                    "power_rating": "150W",
                    "package": "TO-3",
                ]
            ),
        ], root: root)
        let feedURL = try writeVendorFeedCSV(root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","vendor_feed_paths":["\#(feedURL.path)"]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.providers, ["vendor_feed"])
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJ15003G")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.datasheets.first?.providerID, "vendor_feed")
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.evidence.first?.providerID, "vendor_feed")
    }

    func testVendorFeedImportCopiesFeedAndUpdatesProviderConfigForSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let sourceFeedURL = try writeVendorFeedCSV(root: root)

        let importResponse = await sendCatalogImport(
            runtime,
            payload: #"{"vendor_feed_paths":["\#(sourceFeedURL.path)"]}"#
        )

        XCTAssertEqual(importResponse.status, .ok)
        let importedArtifact = try XCTUnwrap(importResponse.artifacts.first { $0.kind == "vendor_feed" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedArtifact.url.path))
        XCTAssertTrue(importedArtifact.url.path.contains("/.merlin/electronics-vendor-feeds/"))
        let configURL = root.appendingPathComponent(".merlin/electronics-provider-config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let paths = try XCTUnwrap(config["vendor_feed_paths"] as? [String])
        XCTAssertEqual(paths, [importedArtifact.url.path])

        let intentURL = try writeIntent(component(refdes: "OUTPUT1", role: "output stage"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                selectedSymbol: "Device:Q_NPN_BCE",
                pins: ["B", "C", "E"],
                constraints: [
                    "component_category": "power_transistor",
                    "polarity": "NPN",
                    "voltage_rating": "120V",
                    "current_rating": "10A",
                    "power_rating": "150W",
                    "package": "TO-3",
                ]
            ),
        ], root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","electronics_provider_config_path":"\#(configURL.path)"}"#
        )

        XCTAssertEqual(selection.status, .ok)
        let matrix = try decodeMatrix(from: selection)
        XCTAssertEqual(matrix.providers, ["vendor_feed"])
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJ15003G")
    }

    func testRuntimeCatalogSelectionAttachesLocalKiCadFootprintEvidence() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RFILT1",
                role: "sweepable boost/cut resistor",
                selectedSymbol: "Device:R",
                selectedFootprint: "Resistor_SMD:R_0603_1608Metric",
                pins: ["1", "2"]
            ),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)
        let symbolsURL = try writeSymbols(root: root)
        let footprintsURL = try writeFootprints(root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"mouser":"\#(mouserURL.path)"},"kicad_symbol_catalog_path":"\#(symbolsURL.path)","kicad_footprint_catalog_path":"\#(footprintsURL.path)"}"#
        )

        XCTAssertEqual(selection.status, .ok)
        let matrix = try decodeMatrix(from: selection)
        let candidate = try XCTUnwrap(matrix.decisions.first?.selectedCandidate)
        XCTAssertEqual(candidate.footprintCandidates.first?.sourceProviderID, "kicad_local")
        XCTAssertEqual(candidate.footprintCandidates.first?.pinPadMap["1"], "1")

        let matrixURL = try XCTUnwrap(selection.artifacts.first { $0.kind == "component_matrix" }).url
        let footprintResponse = await sendFootprints(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(footprintResponse.status, .ok)
        let artifact = try XCTUnwrap(footprintResponse.artifacts.first { $0.kind == "footprint_assignment" })
        let report = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(report.assignments.map(\.refdes), ["RFILT1"])
        XCTAssertEqual(report.assignments.first?.footprint, "Resistor_SMD:R_0603_1608Metric")

        let outputURL = root.appendingPathComponent("compiled", isDirectory: true)
        let compileResponse = await sendCompile(
            runtime,
            payload: #"{"design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixURL.path)","footprint_assignment_path":"\#(artifact.url.path)","output_directory":"\#(outputURL.path)"}"#
        )

        XCTAssertEqual(compileResponse.status, .ok)
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.schematic.rawValue })
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.board.rawValue })
    }

    func testRuntimeCatalogSelectionResolvesLocalFootprintsFromVendorCandidatePackage() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RFILT1",
                role: "sweepable boost/cut resistor",
                selectedSymbol: "Device:R",
                pins: ["1", "2"]
            ),
        ], root: root)
        var vendorCandidate = validCandidate(mpn: "RC0603FR-0710KL", category: "resistor")
        vendorCandidate.package = "0603"
        vendorCandidate.footprintCandidates = []
        let catalogURL = try writeCandidates([vendorCandidate], root: root)
        let footprintsURL = try writeFootprints(root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(catalogURL.path)","kicad_footprint_catalog_path":"\#(footprintsURL.path)"}"#
        )

        XCTAssertEqual(selection.status, .ok)
        let matrix = try decodeMatrix(from: selection)
        let candidate = try XCTUnwrap(matrix.decisions.first?.selectedCandidate)
        let footprint = try XCTUnwrap(candidate.footprintCandidates.first)
        XCTAssertEqual(footprint.sourceProviderID, "kicad_local")
        XCTAssertEqual(footprint.name, "R_0603_1608Metric")
        XCTAssertEqual(footprint.pinPadMap["1"], "1")
        XCTAssertEqual(footprint.pinPadMap["2"], "2")
    }

    func testLocalKiCadFootprintEvidenceToleratesDuplicatePadNames() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Package_TO_SOT_THT:TO-3",
                    pads: [
                        KiCadFootprintPad(number: "1", name: "B"),
                        KiCadFootprintPad(number: "2", name: "C"),
                        KiCadFootprintPad(number: "3", name: "C"),
                    ]
                ),
            ]
        )

        let candidates = try await provider.search(
            ComponentSearchRequest(
                refdes: "QOUT1",
                role: "power transistor",
                constraints: ["footprint": "Package_TO_SOT_THT:TO-3"],
                requiredEvidenceTypes: ["footprint"],
                preferredVendors: [],
                excludedManufacturers: [],
                lifecyclePolicy: "active_or_not_recommended_for_new_design"
            )
        )

        let footprint = try XCTUnwrap(candidates.first?.footprintCandidates.first)
        XCTAssertEqual(footprint.pinPadMap["B"], "1")
        XCTAssertEqual(footprint.pinPadMap["C"], "2")
        XCTAssertEqual(footprint.pinPadMap["3"], "3")
    }

    func testLocalKiCadFootprintRankingPrefersPinCompatibleSpeakerConnector() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Connector_Audio:Jack_3.5mm_CUI_SJ-3523-SMT_Horizontal",
                    pads: numberedPads(["T", "R", "S"])
                ),
                KiCadFootprintDefinition(
                    name: "TerminalBlock_CUI:TerminalBlock_CUI_TB007-508-02_1x02_P5.08mm_Horizontal",
                    pads: numberedPads(["1", "2"])
                ),
                KiCadFootprintDefinition(
                    name: "Connector_Audio:Jack_speakON_Neutrik_NL2MDXX-H-3_Horizontal",
                    pads: numberedPads(["1+", "1-"])
                ),
            ]
        )

        let candidates = try await provider.search(
            ComponentSearchRequest(
                refdes: "JSPK",
                role: "speaker output connector",
                constraints: [
                    "component_category": "speaker_connector",
                    "positions": "2",
                    "required_pins": "1,2",
                    "package": "panel_mount",
                ],
                requiredEvidenceTypes: ["footprint"],
                preferredVendors: [],
                excludedManufacturers: [],
                lifecyclePolicy: "library_asset"
            )
        )

        let footprint = try XCTUnwrap(candidates.first?.footprintCandidates.first)
        XCTAssertEqual(footprint.library, "Connector_Audio")
        XCTAssertEqual(footprint.name, "Jack_speakON_Neutrik_NL2MDXX-H-3_Horizontal")
        XCTAssertEqual(footprint.pinPadMap["1"], "1+")
        XCTAssertEqual(footprint.pinPadMap["2"], "1-")
    }

    func testLocalKiCadFootprintRankingMapsMonoPhoneJackPadsToRequiredPins() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Connector_Audio:Jack_3.5mm_CUI_SJ-3523-SMT_Horizontal",
                    pads: numberedPads(["T", "R", "S"])
                ),
                KiCadFootprintDefinition(
                    name: "Connector_Audio:Jack_6.35mm_Neutrik_NJ2FD-V_Vertical",
                    pads: numberedPads(["T", "S"])
                ),
            ]
        )

        let candidates = try await provider.search(
            ComponentSearchRequest(
                refdes: "JIN",
                role: "high impedance guitar input connector",
                constraints: [
                    "component_category": "phone_audio_jack",
                    "contact_form": "mono",
                    "mounting": "panel_mount",
                    "positions": "2",
                    "required_pins": "1,2",
                ],
                requiredEvidenceTypes: ["footprint"],
                preferredVendors: [],
                excludedManufacturers: [],
                lifecyclePolicy: "library_asset"
            )
        )

        let footprint = try XCTUnwrap(candidates.first?.footprintCandidates.first)
        XCTAssertEqual(footprint.library, "Connector_Audio")
        XCTAssertEqual(footprint.name, "Jack_6.35mm_Neutrik_NJ2FD-V_Vertical")
        XCTAssertEqual(footprint.pinPadMap["1"], "T")
        XCTAssertEqual(footprint.pinPadMap["2"], "S")
    }

    func testRuntimeCatalogSelectionExtractsAndCachesLocalKiCadLibraries() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RFILT1",
                role: "sweepable boost/cut resistor",
                selectedSymbol: "Device:R",
                selectedFootprint: "Resistor_SMD:R_0603_1608Metric",
                pins: ["1", "2"]
            ),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)
        let symbolRoot = try writeKiCadSymbolTree(root: root)
        let footprintRoot = try writeKiCadFootprintTree(root: root)
        let cacheURL = root.appendingPathComponent("kicad-cache", isDirectory: true)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"mouser":"\#(mouserURL.path)"},"kicad_symbol_library_root":"\#(symbolRoot.path)","kicad_footprint_library_root":"\#(footprintRoot.path)","kicad_catalog_cache_directory":"\#(cacheURL.path)","kicad_catalog_cache_ttl_seconds":3600}"#
        )

        XCTAssertEqual(selection.status, .ok)
        let matrix = try decodeMatrix(from: selection)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.footprintCandidates.first?.sourceProviderID, "kicad_local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.appendingPathComponent("kicad-library-catalog.json").path))
    }

    func testRuntimeCatalogSelectionDiscoversKiCadLibraryRootsFromConfig() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RFILT1",
                role: "sweepable boost/cut resistor",
                selectedSymbol: "Device:R",
                selectedFootprint: "Resistor_SMD:R_0603_1608Metric",
                pins: ["1", "2"]
            ),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)
        let installRoot = root.appendingPathComponent("KiCad.app/Contents/SharedSupport/kicad", isDirectory: true)
        _ = try writeKiCadSymbolTree(root: installRoot, directoryName: "symbols")
        _ = try writeKiCadFootprintTree(root: installRoot, directoryName: "footprints")
        let configURL = root.appendingPathComponent("electronics-provider-config.json")
        try """
        {
          "catalog_provider_fixture_paths": {
            "mouser": "\(mouserURL.path)"
          },
          "kicad_library_root_search_paths": ["\(root.path)"],
          "kicad_library_root_cache_directory": "\(root.appendingPathComponent("root-cache").path)",
          "kicad_catalog_cache_directory": "\(root.appendingPathComponent("catalog-cache").path)",
          "kicad_catalog_cache_ttl_seconds": 3600
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","electronics_provider_config_path":"\#(configURL.path)"}"#
        )

        XCTAssertEqual(selection.status, .ok)
        let matrix = try decodeMatrix(from: selection)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.footprintCandidates.first?.sourceProviderID, "kicad_local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("root-cache/kicad-library-roots.json").path))
    }

    func testRuntimeProviderConfigSuppliesFixtureAndCachesProviderCandidates() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)
        let providerCacheURL = root.appendingPathComponent("provider-cache", isDirectory: true)
        let configURL = root.appendingPathComponent("electronics-provider-config.json")
        try """
        {
          "catalog_provider_fixture_paths": {
            "mouser": "\(mouserURL.path)"
          },
          "catalog_cache_directory": "\(providerCacheURL.path)",
          "catalog_cache_ttl_seconds": 3600
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let first = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","electronics_provider_config_path":"\#(configURL.path)"}"#
        )
        XCTAssertEqual(first.status, .ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: providerCacheURL.appendingPathComponent("mouser-candidates.json").path))

        try FileManager.default.removeItem(at: mouserURL)
        let cached = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","electronics_provider_config_path":"\#(configURL.path)"}"#
        )

        XCTAssertEqual(cached.status, .ok)
        let matrix = try decodeMatrix(from: cached)
        XCTAssertEqual(matrix.providers, ["mouser"])
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "RC0603FR-0710KL")
        XCTAssertEqual(matrix.cacheMetadata["source"], "runtime_catalog_providers")
    }

    func testExplicitLiveCatalogProviderWithoutCredentialsBlocksTruthfully() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","live_catalog_providers":["mouser"],"mouser_api_key_env":"MERLIN_TEST_MISSING_MOUSER_API_KEY","mouser_api_key_keychain_id":"merlin.test.missing.mouser.api_key"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "CATALOG_PROVIDER_NOT_CONFIGURED" })
        let matrix = try decodeMatrix(from: response)
        XCTAssertTrue(matrix.warnings.contains { $0.contains("CATALOG_PROVIDER_NOT_CONFIGURED") })
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
    }

    func testPluginSettingsEnabledProvidersDefaultLiveCatalogProviderList() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(
            namespace: ElectronicsRuntimePlugin.settingsNamespace,
            values: [
                "catalog_provider_mouser_enabled": .boolean(true),
                "catalog_provider_digikey_enabled": .boolean(true),
                "catalog_provider_nexar_enabled": .boolean(false),
                "catalog_provider_trustedparts_enabled": .boolean(false),
            ]
        ))
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","mouser_api_key_env":"MERLIN_TEST_MISSING_MOUSER_API_KEY","mouser_api_key_keychain_id":"merlin.test.missing.mouser.api_key","digikey_client_id_env":"MERLIN_TEST_MISSING_DIGIKEY_CLIENT_ID","digikey_client_id_keychain_id":"merlin.test.missing.digikey.client_id","digikey_client_secret_env":"MERLIN_TEST_MISSING_DIGIKEY_CLIENT_SECRET","digikey_client_secret_keychain_id":"merlin.test.missing.digikey.client_secret","digikey_access_token_env":"MERLIN_TEST_MISSING_DIGIKEY_ACCESS_TOKEN","digikey_access_token_keychain_id":"merlin.test.missing.digikey.access_token"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertTrue(matrix.warnings.contains { $0.contains("CATALOG_PROVIDER_NOT_CONFIGURED: mouser") })
        XCTAssertTrue(matrix.warnings.contains { $0.contains("CATALOG_PROVIDER_NOT_CONFIGURED: digikey") })
        XCTAssertFalse(matrix.warnings.contains { $0.contains("nexar") })
        XCTAssertFalse(matrix.warnings.contains { $0.contains("trustedparts") })
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
    }

    func testLiveCatalogQueryUsesStructuredIntentInsteadOfKiCadSymbolName() throws {
        let request = ComponentSearchRequest(
            refdes: "RFILT1",
            role: "sweepable boost/cut resistor",
            constraints: [
                "selected_symbol": "Device:R",
                "required_pins": "1,2",
            ],
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: ["mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        )

        let query = CatalogSearchQueryBuilder().keyword(for: request)

        XCTAssertNotEqual(query, "Device:R")
        XCTAssertTrue(query.contains("resistor"))
        XCTAssertFalse(query.contains("Device:R"))
    }

    func testTargetedLiveCandidateStillMustMatchComponentCategory() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)
        var wrongTargeted = validCandidate(mpn: "1N4148W", category: "switching_diodes")
        wrongTargeted.evidence = wrongTargeted.evidence.map { evidence in
            var evidence = evidence
            evidence.extractedParameters["target_refdes"] = "RFILT1"
            return evidence
        }
        let rightResistor = validCandidate(mpn: "RC0603FR-0710KL", category: "resistors")
        let candidatesURL = try writeCandidates([wrongTargeted, rightResistor], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(candidatesURL.path)","live_catalog_providers":[]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "RC0603FR-0710KL")
    }

    func testFixedResistorSlotRejectsPotentiometerAndSelectsVendorBackedFixedResistor() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "TONE1", role: "3-band tone circuit"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RMID1",
                role: "mid tone resistor",
                selectedSymbol: "Device:R",
                pins: ["1", "2"],
                constraints: [
                    "component_category": "resistor",
                    "resistance": "25kOhm",
                    "power_rating": "0.25W",
                    "tolerance": "1%",
                    "package": "through_hole_axial",
                ]
            ),
        ], root: root)
        let potentiometer = catalogCandidate(
            refdes: "RMID1",
            mpn: "PT15LV18-253A2020-S",
            manufacturer: "Amphenol Piher",
            category: "potentiometers",
            value: "Potentiometer 25 kOhms through hole",
            package: "through_hole",
            ratings: ["resistance": "25 kOhms", "power_w": "0.25", "tolerance": "20%"]
        )
        let fixedResistor = catalogCandidate(
            refdes: "RMID1",
            mpn: "MFR-25FBF52-25K",
            manufacturer: "YAGEO",
            category: "through_hole_resistors",
            value: "Metal Film Resistors 25 kOhms 1% 1/4W Axial",
            package: "Axial",
            ratings: ["resistance": "25 kOhms", "power_w": "0.25", "tolerance": "1%"]
        )
        let candidatesURL = try writeCandidates([potentiometer, fixedResistor], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(candidatesURL.path)","live_catalog_providers":[]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MFR-25FBF52-25K")
    }

    func testLiveCatalogCacheCanSelectWithoutCredentialsOnLaterRun() async throws {
        let root = try temporaryDirectory()
        let cacheDirectory = root.appendingPathComponent(".merlin/electronics-catalog-cache", isDirectory: true)
        let cachedCandidate = validCandidate(mpn: "RC0603FR-0710KL", category: "resistor")
        let query = CatalogSearchQueryBuilder().keyword(for: ComponentSearchRequest(
            refdes: "RFILT1",
            role: "sweepable boost/cut resistor",
            constraints: [
                "selected_symbol": "Device:R",
                "source": "circuit_ir",
                "required_pins": "1,2",
            ],
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: ["mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        ))
        XCTAssertNotEqual(query, "Device:R")
        try LiveCatalogQueryCache().write(
            candidates: [cachedCandidate],
            rawResponse: Data(#"{"SearchResults":{"Parts":[]}}"#.utf8),
            providerID: "mouser",
            query: query,
            requestURL: URL(string: "https://api.mouser.test/api/v2/search/keyword"),
            to: cacheDirectory,
            now: Date()
        )
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","live_catalog_providers":["mouser"]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.cacheMetadata["source"], "live_catalog_cache")
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "RC0603FR-0710KL")
    }

    func testSourcePolicyJSONCanProvideLiveCatalogProvidersAndCircuitIRPath() async throws {
        let root = try temporaryDirectory()
        let cacheDirectory = root.appendingPathComponent(".merlin/electronics-catalog-cache", isDirectory: true)
        let cachedCandidate = validCandidate(mpn: "RC0603FR-0710KL", category: "resistor")
        let query = CatalogSearchQueryBuilder().keyword(for: ComponentSearchRequest(
            refdes: "RFILT1",
            role: "sweepable boost/cut resistor",
            constraints: [
                "selected_symbol": "Device:R",
                "source": "circuit_ir",
                "required_pins": "1,2",
            ],
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: ["mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        ))
        try LiveCatalogQueryCache().write(
            candidates: [cachedCandidate],
            rawResponse: Data(#"{"SearchResults":{"Parts":[]}}"#.utf8),
            providerID: "mouser",
            query: query,
            requestURL: URL(string: "https://api.mouser.test/api/v2/search/keyword"),
            to: cacheDirectory,
            now: Date()
        )
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)
        let sourcePolicy = #"{"circuit_ir_path":"\#(circuitIRURL.path)","live_catalog_providers":["mouser"],"live_catalog_result_limit":3}"#

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","source_policy_json":"\#(sourcePolicy.replacingOccurrences(of: "\"", with: "\\\""))"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.cacheMetadata["source"], "live_catalog_cache")
        XCTAssertEqual(matrix.decisions.first?.status, .selected)
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "RC0603FR-0710KL")
    }

    func testDisabledPluginCatalogProviderIsNotQueriedEvenWhenRequested() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(
            namespace: ElectronicsRuntimePlugin.settingsNamespace,
            values: ["catalog_provider_mouser_enabled": .boolean(false)]
        ))
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","live_catalog_providers":["mouser"]}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertTrue(matrix.providers.isEmpty)
        XCTAssertFalse(matrix.warnings.contains { $0.contains("CATALOG_PROVIDER_NOT_CONFIGURED") })
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
    }

    func testTrustedPartsDisabledPluginCatalogProviderIsNotQueriedEvenWhenRequested() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(
            namespace: ElectronicsRuntimePlugin.settingsNamespace,
            values: ["catalog_provider_trustedparts_enabled": .boolean(false)]
        ))
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "QOUT1",
                role: "single-ended Class-A output transistor",
                selectedSymbol: "Transistor_BJT:MJ15003G",
                pins: ["1", "2", "3"],
                constraints: ["manufacturer_part_number": "MJ15003G"]
            ),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","live_catalog_providers":["trustedparts"]}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let matrix = try decodeMatrix(from: response)
        XCTAssertTrue(matrix.providers.isEmpty)
        XCTAssertFalse(matrix.warnings.contains { $0.contains("CATALOG_PROVIDER_NOT_CONFIGURED") })
        XCTAssertEqual(matrix.decisions.first?.status, .requiresVendorResolution)
    }

    func testAmpDemoLiveCatalogSelectionSelectsWithLiveEvidence() async throws {
        let runSentinel = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-live-catalog-slice")
        guard ProcessInfo.processInfo.environment["RUN_AMPDEMO_LIVE_CATALOG"] == "1"
            || FileManager.default.fileExists(atPath: runSentinel.path)
        else {
            throw XCTSkip("Set RUN_AMPDEMO_LIVE_CATALOG=1 or create \(runSentinel.path) to run the AmpDemo live catalog slice.")
        }

        let root = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo", isDirectory: true)
        let artifactsURL = root.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let intentURL = try newestApprovedDesignIntent(in: artifactsURL)
        let circuitIRURL = try newestArtifact(in: artifactsURL, suffix: "circuit_ir.json")
        for url in [intentURL, circuitIRURL] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(url.path)")
        }

        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(
            namespace: ElectronicsRuntimePlugin.settingsNamespace,
            values: [
                "catalog_provider_mouser_enabled": .boolean(true),
                "catalog_provider_digikey_enabled": .boolean(true),
                "catalog_provider_nexar_enabled": .boolean(false),
                "catalog_provider_trustedparts_enabled": .boolean(false),
            ]
        ))

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        let matrix = try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(Set(matrix.providers), Set(["mouser", "digikey"]))
        XCTAssertFalse(matrix.providers.contains("nexar"))
        XCTAssertFalse(matrix.providers.contains("trustedparts"))
        XCTAssertTrue(matrix.decisions.contains { decision in
            decision.candidateSet.contains { candidate in
                candidate.evidence.contains { ["mouser", "digikey"].contains($0.providerID) }
            }
        })
        XCTAssertFalse(matrix.decisions.isEmpty)
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.status == .selected })
        for decision in matrix.decisions {
            let candidate = try XCTUnwrap(decision.selectedCandidate)
            XCTAssertFalse(candidate.evidence.isEmpty, "Selected \(decision.refdes) without provider evidence.")
            XCTAssertFalse(candidate.datasheets.isEmpty, "Selected \(decision.refdes) without datasheet evidence.")
            XCTAssertFalse(candidate.ratings.isEmpty, "Selected \(decision.refdes) without extracted ratings.")
        }
        print("AmpDemo live component matrix: \(artifact.url.path)")
    }

    func testAmpDemoVendorFeedImportAndSelectionUsesLocalFeedOnly() async throws {
        let runSentinel = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-vendor-feed-slice")
        guard ProcessInfo.processInfo.environment["RUN_AMPDEMO_VENDOR_FEED_SLICE"] == "1"
            || FileManager.default.fileExists(atPath: runSentinel.path)
        else {
            throw XCTSkip("Set RUN_AMPDEMO_VENDOR_FEED_SLICE=1 or create \(runSentinel.path) to run the AmpDemo vendor feed slice.")
        }

        let root = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo", isDirectory: true)
        let artifactsURL = root.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let intentURL = try newestApprovedDesignIntent(in: artifactsURL)
        let circuitIRURL = try newestArtifact(in: artifactsURL, suffix: "circuit_ir.json")
        let sourceFeedURL = root.appendingPathComponent("vendor-feeds/ampdemo-25w-vendor-feed.csv")
        for url in [intentURL, circuitIRURL, sourceFeedURL] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(url.path)")
        }

        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(
            namespace: ElectronicsRuntimePlugin.settingsNamespace,
            values: [
                "catalog_provider_vendor_feed_enabled": .boolean(true),
                "catalog_provider_mouser_enabled": .boolean(false),
                "catalog_provider_digikey_enabled": .boolean(false),
                "catalog_provider_nexar_enabled": .boolean(false),
                "catalog_provider_trustedparts_enabled": .boolean(false),
            ]
        ))

        let importResponse = await sendCatalogImport(
            runtime,
            payload: #"{"vendor_feed_paths":["\#(sourceFeedURL.path)"]}"#
        )
        XCTAssertEqual(importResponse.status, .ok)
        let importedFeed = try XCTUnwrap(importResponse.artifacts.first { $0.kind == "vendor_feed" })
        let configURL = try XCTUnwrap(importResponse.artifacts.first { $0.kind == "provider_config" }).url

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","electronics_provider_config_path":"\#(configURL.path)","live_catalog_providers":[]}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.providers, ["vendor_feed"])
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.status == .selected }, "Vendor feed should cover every AmpDemo selection decision.")
        XCTAssertTrue(matrix.decisions.allSatisfy { decision in
            decision.selectedCandidate?.evidence.contains { $0.providerID == "vendor_feed" } == true
        })
        XCTAssertTrue(matrix.decisions.contains { $0.refdes == "QOUT1" && $0.selectedCandidate?.mpn == "MJ15003G" })
        XCTAssertTrue(matrix.decisions.contains { $0.refdes == "BR1" && $0.selectedCandidate?.mpn == "GBU8J-E3/45" })
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        print("AmpDemo imported vendor feed: \(importedFeed.url.path)")
        print("AmpDemo vendor-feed component matrix: \(artifact.url.path)")
    }

    func testAmpDemoSelectedMatrixAssignsEvidenceBackedFootprints() async throws {
        let runSentinel = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-footprint-slice")
        guard ProcessInfo.processInfo.environment["RUN_AMPDEMO_FOOTPRINT_SLICE"] == "1"
            || FileManager.default.fileExists(atPath: runSentinel.path)
        else {
            throw XCTSkip("Set RUN_AMPDEMO_FOOTPRINT_SLICE=1 or create \(runSentinel.path) to run the AmpDemo footprint slice.")
        }

        let root = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo", isDirectory: true)
        let artifactsURL = root.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let intentURL = try newestApprovedDesignIntent(in: artifactsURL)
        let circuitIRURL = try newestArtifact(in: artifactsURL, suffix: "circuit_ir.json")
        let matrixURL = try newestArtifact(in: artifactsURL, suffix: "component_matrix.json")
        let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: circuitIRURL))
        let matrix = try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: matrixURL))
        XCTAssertFalse(matrix.providers.isEmpty, "AmpDemo footprint slice requires catalog provider evidence.")
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.status == .selected })
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.selectedCandidate?.evidence.isEmpty == false })
        let footprintCatalogURL = try writeAmpDemoFootprints(root: try temporaryDirectory())

        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let response = await sendFootprints(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixURL.path)","kicad_footprint_catalog_path":"\#(footprintCatalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "footprint_assignment" })
        let report = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(report.assignments.count, circuitIR.components.count)
        XCTAssertEqual(report.unknownFootprints, 0)
        let assignmentsByRefdes = Dictionary(uniqueKeysWithValues: report.assignments.map { ($0.refdes, $0) })
        for component in circuitIR.components {
            let assignment = try XCTUnwrap(assignmentsByRefdes[component.refdes], "Missing footprint for \(component.refdes)")
            XCTAssertEqual(assignment.sourceProviderID, "kicad_local")
            XCTAssertFalse(assignment.footprint.isEmpty)
            XCTAssertFalse(assignment.packageCompatibilityEvidence.isEmpty)
            let requiredPins = component.pins.compactMap { pin -> String? in
                let canonical = pin.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !canonical.isEmpty { return canonical }
                let symbol = pin.symbolPin.trimmingCharacters(in: .whitespacesAndNewlines)
                if !symbol.isEmpty { return symbol }
                let number = pin.pinNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                return number.isEmpty ? nil : number
            }
            XCTAssertTrue(
                requiredPins.allSatisfy { assignment.pinPadMap[$0]?.isEmpty == false },
                "Missing pin-pad evidence for \(component.refdes)."
            )
        }
        print("AmpDemo footprint assignment: \(artifact.url.path)")
    }

    func testAmpDemoEvidenceBackedSchematicCompileRejectsCaricatureOutput() async throws {
        let runSentinel = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-schematic-slice")
        guard ProcessInfo.processInfo.environment["RUN_AMPDEMO_SCHEMATIC_SLICE"] == "1"
            || FileManager.default.fileExists(atPath: runSentinel.path)
        else {
            throw XCTSkip("Set RUN_AMPDEMO_SCHEMATIC_SLICE=1 or create \(runSentinel.path) to run the AmpDemo schematic slice.")
        }

        let root = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo", isDirectory: true)
        let artifactsURL = root.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let intentURL = try newestApprovedDesignIntent(in: artifactsURL)
        let circuitIRURL = try newestArtifact(in: artifactsURL, suffix: "circuit_ir.json")
        let matrixURL = try newestArtifact(in: artifactsURL, suffix: "component_matrix.json")
        let footprintURL = try newestArtifact(in: artifactsURL, suffix: "footprint_assignment.json")
        let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: circuitIRURL))
        let matrix = try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: matrixURL))
        let footprints = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: footprintURL))
        XCTAssertFalse(matrix.providers.isEmpty, "AmpDemo schematic slice requires catalog provider evidence.")
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.status == .selected && $0.selectedCandidate != nil })
        XCTAssertTrue(matrix.decisions.allSatisfy { $0.selectedCandidate?.evidence.isEmpty == false })
        XCTAssertEqual(footprints.assignments.count, circuitIR.components.count)
        XCTAssertEqual(footprints.unknownFootprints, 0)

        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let outputURL = root
            .appendingPathComponent(".merlin/schematic-slice", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let compileResponse = await sendCompile(
            runtime,
            payload: #"{"design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixURL.path)","footprint_assignment_path":"\#(footprintURL.path)","output_directory":"\#(outputURL.path)"}"#
        )

        XCTAssertEqual(compileResponse.status, .ok)
        let schematicArtifact = try XCTUnwrap(compileResponse.artifacts.first { $0.kind == ElectronicsArtifactKind.schematic.rawValue })
        let schematicText = try String(contentsOf: schematicArtifact.url, encoding: .utf8)
        let schematic = try KiCadSchematicParser().parse(schematicText)
        XCTAssertEqual(schematic.symbols.count, circuitIR.components.count)
        XCTAssertFalse(schematic.symbols.contains { $0.emitsKiCadSymbol == false })

        let symbolsByRefdes = Dictionary(uniqueKeysWithValues: schematic.symbols.compactMap { symbol -> (String, KiCadSchematicDocument.Symbol)? in
            guard let refdes = symbol.property(named: "Reference") else { return nil }
            return (refdes, symbol)
        })
        let decisionsByRefdes = Dictionary(uniqueKeysWithValues: matrix.decisions.map { ($0.refdes, $0) })
        let footprintsByRefdes = Dictionary(uniqueKeysWithValues: footprints.assignments.map { ($0.refdes, $0) })
        for component in circuitIR.components {
            let symbol = try XCTUnwrap(symbolsByRefdes[component.refdes], "Missing real schematic symbol for \(component.refdes)")
            let candidate = try XCTUnwrap(decisionsByRefdes[component.refdes]?.selectedCandidate)
            let assignment = try XCTUnwrap(footprintsByRefdes[component.refdes])
            XCTAssertEqual(symbol.property(named: "Symbol"), component.selectedSymbol)
            XCTAssertEqual(symbol.property(named: "Footprint"), assignment.footprint)
            XCTAssertEqual(symbol.property(named: "ManufacturerPartNumber"), candidate.mpn)
            XCTAssertNotEqual(symbol.property(named: "Value"), component.role)
            XCTAssertFalse((symbol.property(named: "SourceEvidence") ?? "").isEmpty)
            XCTAssertFalse((symbol.property(named: "Pins") ?? "").isEmpty)
        }

        let schematicLabels = Set(schematic.labels.map(\.text))
        for net in circuitIR.nets where !net.endpoints.isEmpty {
            XCTAssertTrue(schematicLabels.contains(net.name), "Missing schematic net label \(net.name)")
        }

        let kicadCLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
        guard FileManager.default.isExecutableFile(atPath: kicadCLI) else {
            print("AmpDemo schematic: \(schematicArtifact.url.path)")
            throw XCTSkip("KiCad CLI is not installed at \(kicadCLI)")
        }
        let projectArtifact = try XCTUnwrap(compileResponse.artifacts.first { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
        let ercResponse = await sendERC(
            runtime,
            payload: #"{"project_path":"\#(projectArtifact.url.path)","kicad_cli_path":"\#(kicadCLI)"}"#
        )
        XCTAssertTrue([WorkspaceMessageResponseStatus.ok, WorkspaceMessageResponseStatus.blocked].contains(ercResponse.status))
        let ercArtifact = try XCTUnwrap(ercResponse.artifacts.first { $0.kind == "erc_report" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: ercArtifact.url.path))
        print("AmpDemo schematic: \(schematicArtifact.url.path)")
        print("AmpDemo ERC report: \(ercArtifact.url.path)")
    }

    func testAmpDemoEvidenceBackedPCBCompilePlacesAllFootprintsAndRunsDRC() async throws {
        let runSentinel = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-pcb-slice")
        guard ProcessInfo.processInfo.environment["RUN_AMPDEMO_PCB_SLICE"] == "1"
            || FileManager.default.fileExists(atPath: runSentinel.path)
        else {
            throw XCTSkip("Set RUN_AMPDEMO_PCB_SLICE=1 or create \(runSentinel.path) to run the AmpDemo PCB slice.")
        }

        let root = URL(fileURLWithPath: "/Users/jonzuilkowski/Documents/localProject/AmpDemo", isDirectory: true)
        let artifactsURL = root.appendingPathComponent(".merlin/electronics-artifacts", isDirectory: true)
        let intentURL = try newestApprovedDesignIntent(in: artifactsURL)
        let matrixURL = try newestArtifact(in: artifactsURL, suffix: "component_matrix.json")
        let footprintURL = try newestArtifact(in: artifactsURL, suffix: "footprint_assignment.json")

        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let circuitIRResponse = await sendCircuitIR(
            runtime,
            payload: #"{"design_intent_path":"\#(intentURL.path)"}"#
        )
        XCTAssertEqual(circuitIRResponse.status, .ok)
        let circuitIRURL = try XCTUnwrap(circuitIRResponse.artifacts.first { $0.kind == "circuit_ir" }).url
        let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: circuitIRURL))
        let footprints = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: footprintURL))

        let outputURL = root
            .appendingPathComponent(".merlin/pcb-slice", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let compileResponse = await sendCompile(
            runtime,
            payload: #"{"design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixURL.path)","footprint_assignment_path":"\#(footprintURL.path)","output_directory":"\#(outputURL.path)"}"#
        )

        XCTAssertEqual(compileResponse.status, .ok)
        let boardArtifact = try XCTUnwrap(compileResponse.artifacts.first { $0.kind == ElectronicsArtifactKind.board.rawValue })
        let projectArtifact = try XCTUnwrap(compileResponse.artifacts.first { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
        let boardText = try String(contentsOf: boardArtifact.url, encoding: .utf8)
        XCTAssertTrue(boardText.contains(#""Edge.Cuts""#), "PCB must include a board outline.")
        XCTAssertEqual(boardText.components(separatedBy: #"(footprint ""#).count - 1, circuitIR.components.count)

        let assignmentsByRefdes = Dictionary(uniqueKeysWithValues: footprints.assignments.map { ($0.refdes, $0) })
        for component in circuitIR.components {
            let assignment = try XCTUnwrap(assignmentsByRefdes[component.refdes])
            XCTAssertTrue(boardText.contains(#"(property "Reference" "\#(component.refdes)""#), "Missing placed reference for \(component.refdes)")
            XCTAssertTrue(boardText.contains(#"(footprint "\#(assignment.footprint)""#), "Missing assigned footprint \(assignment.footprint)")
            for pad in Set(assignment.pinPadMap.values) {
                XCTAssertTrue(boardText.contains(#"(pad "\#(pad)""#), "Missing pad \(pad) for \(component.refdes)")
            }
        }
        for net in circuitIR.nets where !net.endpoints.isEmpty {
            XCTAssertTrue(boardText.contains(#""\#(net.name)""#), "Missing PCB net \(net.name)")
        }

        let kicadCLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
        guard FileManager.default.isExecutableFile(atPath: kicadCLI) else {
            print("AmpDemo PCB: \(boardArtifact.url.path)")
            throw XCTSkip("KiCad CLI is not installed at \(kicadCLI)")
        }
        let drcResponse = await sendDRC(
            runtime,
            payload: #"{"project_path":"\#(projectArtifact.url.path)","kicad_cli_path":"\#(kicadCLI)"}"#
        )
        XCTAssertTrue([WorkspaceMessageResponseStatus.ok, WorkspaceMessageResponseStatus.blocked].contains(drcResponse.status))
        let drcArtifact = try XCTUnwrap(drcResponse.artifacts.first { $0.kind == "drc_report" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: drcArtifact.url.path))
        let drcReport = try KiCadDRCParser().parse(jsonData: Data(contentsOf: drcArtifact.url))
        let libraryFootprintViolations = drcReport.violations.filter {
            $0.code == "lib_footprint_issues" || $0.code == "lib_footprint_mismatch"
        }
        XCTAssertTrue(
            libraryFootprintViolations.isEmpty,
            "PCB must embed real KiCad library footprints; library footprint DRC violations: \(libraryFootprintViolations)"
        )
        let placementViolations = drcReport.violations.filter {
            ["courtyards_overlap", "pth_inside_courtyard", "silk_overlap"].contains($0.code)
        }
        XCTAssertTrue(
            placementViolations.isEmpty,
            "PCB placement must leave enough space for footprint courtyards, PTH pads, and silkscreen: \(placementViolations)"
        )
        let unconnectedViolations = drcReport.violations.filter { $0.code == "unconnected_items" }
        XCTAssertTrue(
            unconnectedViolations.isEmpty,
            "PCB routing must connect every routed net endpoint: \(unconnectedViolations)"
        )
        XCTAssertTrue(
            drcReport.blockingViolations.isEmpty,
            "PCB DRC must be clean before the PCB slice is considered verified: \(drcReport.blockingViolations)"
        )
        print("AmpDemo PCB: \(boardArtifact.url.path)")
        print("AmpDemo DRC report: \(drcArtifact.url.path)")
    }

    private func newestApprovedDesignIntent(in directory: URL) throws -> URL {
        let candidates = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasSuffix("design_intent.json") }
            .filter { url in
                guard let data = try? Data(contentsOf: url),
                      let intent = try? JSONDecoder().decode(DesignIntent.self, from: data) else {
                    return false
                }
                return intent.approval.status == .approved
            }
        return try XCTUnwrap(
            newestURL(candidates),
            "Missing approved DesignIntent artifact in \(directory.path)"
        )
    }

    private func newestArtifact(in directory: URL, suffix: String) throws -> URL {
        let candidates = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
        return try XCTUnwrap(
            newestURL(candidates),
            "Missing \(suffix) artifact in \(directory.path)"
        )
    }

    private func newestURL(_ urls: [URL]) -> URL? {
        urls.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    func testWorkflowHandoffCarriesArtifactPathsAcrossEvidencePipeline() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(
                refdes: "RFILT1",
                role: "sweepable boost/cut resistor",
                selectedSymbol: "Device:R",
                selectedFootprint: "Resistor_SMD:R_0603_1608Metric",
                pins: ["1", "2"]
            ),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)
        let symbolsURL = try writeSymbols(root: root)
        let footprintsURL = try writeFootprints(root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"mouser":"\#(mouserURL.path)"},"kicad_symbol_catalog_path":"\#(symbolsURL.path)","kicad_footprint_catalog_path":"\#(footprintsURL.path)"}"#
        )
        let selectionResult = try XCTUnwrap(selection.payload?.decodeJSON(KiCadToolResult.self))
        let handoffAfterSelection = try XCTUnwrap(selectionResult.handoff)
        XCTAssertEqual(handoffAfterSelection.designIntentPath, intentURL.path)
        XCTAssertEqual(handoffAfterSelection.circuitIRPath, circuitIRURL.path)
        let matrixPath = try XCTUnwrap(handoffAfterSelection.componentMatrixPath)

        let footprintResponse = await sendFootprints(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(handoffAfterSelection.designIntentPath ?? "")","circuit_ir_path":"\#(handoffAfterSelection.circuitIRPath ?? "")","component_matrix_path":"\#(matrixPath)"}"#
        )
        let footprintResult = try XCTUnwrap(footprintResponse.payload?.decodeJSON(KiCadToolResult.self))
        let handoffAfterFootprints = try XCTUnwrap(footprintResult.handoff)
        XCTAssertEqual(handoffAfterFootprints.componentMatrixPath, matrixPath)
        XCTAssertNotNil(handoffAfterFootprints.footprintAssignmentPath)
    }

    func testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let fixtureRoot = repoRoot().appendingPathComponent("plugins/electronics/fixtures/amp_low_voltage_audio")
        let intentURL = fixtureRoot.appendingPathComponent("design_intent.json")
        let circuitIRURL = fixtureRoot.appendingPathComponent("circuit_ir.json")
        let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: circuitIRURL))
        let candidatesURL = try writeAmpCandidates(from: circuitIR, root: root)
        let symbolsURL = try writeSymbols(from: circuitIR, root: root)
        let footprintsURL = try writeFootprints(from: circuitIR, root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp_low_voltage_audio","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_candidates_path":"\#(candidatesURL.path)","kicad_symbol_catalog_path":"\#(symbolsURL.path)","kicad_footprint_catalog_path":"\#(footprintsURL.path)"}"#
        )
        XCTAssertEqual(selection.status, .ok)
        let selectionHandoff = try XCTUnwrap(selection.payload?.decodeJSON(KiCadToolResult.self).handoff)
        let matrixPath = try XCTUnwrap(selectionHandoff.componentMatrixPath)

        let footprintResponse = await sendFootprints(
            runtime,
            payload: #"{"design_id":"amp_low_voltage_audio","design_intent_path":"\#(selectionHandoff.designIntentPath ?? "")","circuit_ir_path":"\#(selectionHandoff.circuitIRPath ?? "")","component_matrix_path":"\#(matrixPath)"}"#
        )
        XCTAssertEqual(footprintResponse.status, .ok)
        let footprintHandoff = try XCTUnwrap(footprintResponse.payload?.decodeJSON(KiCadToolResult.self).handoff)
        let assignmentPath = try XCTUnwrap(footprintHandoff.footprintAssignmentPath)

        let outputURL = root.appendingPathComponent("compiled", isDirectory: true)
        let compileResponse = await sendCompile(
            runtime,
            payload: #"{"design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixPath)","footprint_assignment_path":"\#(assignmentPath)","output_directory":"\#(outputURL.path)"}"#
        )

        XCTAssertEqual(compileResponse.status, .ok)
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.schematic.rawValue })
        XCTAssertTrue(compileResponse.artifacts.contains { $0.kind == ElectronicsArtifactKind.board.rawValue })
        let schematic = try XCTUnwrap(compileResponse.artifacts.first { $0.kind == ElectronicsArtifactKind.schematic.rawValue })
        let schematicText = try String(contentsOf: schematic.url, encoding: .utf8)
        XCTAssertTrue(schematicText.contains("QOUT1"))
        XCTAssertTrue(schematicText.contains("RBASS"))
    }

    func testBoardMaterializerEmbedsRealKiCadFootprintBodyAndNets() throws {
        let root = try temporaryDirectory()
        let footprintRoot = try writeKiCadFootprintTree(root: root)
        let outputURL = root.appendingPathComponent("compiled", isDirectory: true)
        let circuitIR = CircuitIR(
            designId: "resistor-test",
            boardId: "resistor-test",
            components: [
                CircuitComponent(
                    refdes: "R1",
                    role: "test resistor",
                    selectedSymbol: "Device:R",
                    selectedFootprint: "Resistor_SMD:R_0603_1608Metric",
                    manufacturerPartNumber: "RC0603FR-0710KL",
                    sourceEvidence: [SourceEvidence(kind: "test", reference: "fixture")],
                    pins: [
                        CircuitPin(componentRefdes: "R1", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "R1", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ],
                    constraints: ["value": "10k"]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "VIN",
                    role: "input",
                    endpoints: [CircuitNetEndpoint(componentRefdes: "R1", pinNumber: "1")],
                    netClass: "signal",
                    safetyDomain: "low_voltage"
                ),
                CircuitNet(
                    name: "VOUT",
                    role: "output",
                    endpoints: [CircuitNetEndpoint(componentRefdes: "R1", pinNumber: "2")],
                    netClass: "signal",
                    safetyDomain: "low_voltage"
                ),
            ],
            constraints: [],
            verificationScenarios: []
        )

        let materialized = try CircuitIRKiCadBoardMaterializer(footprintRoot: footprintRoot).materialize(
            circuitIR: circuitIR,
            outputDirectory: outputURL
        )

        let boardText = try String(contentsOf: materialized.boardURL, encoding: .utf8)
        XCTAssertTrue(boardText.contains(#"(footprint "Resistor_SMD:R_0603_1608Metric""#))
        XCTAssertTrue(boardText.contains(#"(property "Reference" "R1""#))
        XCTAssertTrue(boardText.contains(#"(property "Value" "10k""#))
        XCTAssertTrue(boardText.contains(#"(pad "1" smd roundrect"#), "The board must embed the real library pad geometry, not a synthetic through-hole pad.")
        XCTAssertTrue(boardText.contains(#"(net 1 "VIN")"#))
        XCTAssertTrue(boardText.contains(#"(net 2 "VOUT")"#))
        XCTAssertFalse(boardText.contains(#"(pad "1" thru_hole circle"#))
    }

    func testBoardMaterializerRejectsEndpointAssignedToMultipleNets() throws {
        let root = try temporaryDirectory()
        let outputURL = root.appendingPathComponent("compiled", isDirectory: true)
        let circuitIR = CircuitIR(
            designId: "net-conflict-test",
            boardId: "net-conflict-test",
            components: [
                CircuitComponent(
                    refdes: "J1",
                    role: "test connector",
                    selectedSymbol: "Connector_Generic:Conn_01x02",
                    selectedFootprint: "Connector_Generic:Conn_01x02",
                    manufacturerPartNumber: nil,
                    sourceEvidence: [SourceEvidence(kind: "test", reference: "fixture")],
                    pins: [
                        CircuitPin(componentRefdes: "J1", pinNumber: "1", canonicalName: "1", electricalType: "passive", symbolPin: "1", footprintPad: "1"),
                        CircuitPin(componentRefdes: "J1", pinNumber: "2", canonicalName: "2", electricalType: "passive", symbolPin: "2", footprintPad: "2"),
                    ],
                    constraints: [:]
                ),
            ],
            nets: [
                CircuitNet(name: "VRAW", role: "raw supply", endpoints: [CircuitNetEndpoint(componentRefdes: "J1", pinNumber: "1")], netClass: "power", safetyDomain: "isolated_secondary"),
                CircuitNet(name: "GND", role: "common", endpoints: [CircuitNetEndpoint(componentRefdes: "J1", pinNumber: "1")], netClass: "ground", safetyDomain: "isolated_secondary"),
            ],
            constraints: [],
            verificationScenarios: []
        )

        XCTAssertThrowsError(try CircuitIRKiCadBoardMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputURL
        )) { error in
            guard case CircuitIRKiCadBoardMaterializerError.invalidBoardEvidence(let issues) = error else {
                return XCTFail("Expected invalid board evidence, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.code == "PCB_ENDPOINT_NET_CONFLICT" })
        }
    }

    func testRuntimeCatalogSelectionWithoutFootprintEvidenceStillBlocksAssignment() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "FILTER1", role: "sweepable boost/cut filter"), root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
        ], root: root)
        let mouserURL = try writeMouserFixture(root: root)

        let selection = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","catalog_provider_fixture_paths":{"mouser":"\#(mouserURL.path)"}}"#
        )
        let matrixURL = try XCTUnwrap(selection.artifacts.first { $0.kind == "component_matrix" }).url

        let footprintResponse = await sendFootprints(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(footprintResponse.status, .blocked)
        let result = try XCTUnwrap(footprintResponse.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "FOOTPRINT_CANDIDATE_REQUIRED" })
    }

    private func decodeMatrix(from response: WorkspaceMessageResponse) throws -> ComponentMatrix {
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        return try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: artifact.url))
    }

    private func component(refdes: String, role: String, constraints: [String: String] = [:]) -> ComponentIntent {
        ComponentIntent(
            refdes: refdes,
            role: role,
            constraints: ["implementation": "discrete"].merging(constraints) { _, new in new }
        )
    }

    private func writeIntent(_ component: ComponentIntent, root: URL) throws -> URL {
        let intent = DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-05-30T15:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Evidence-gated component selection", priority: "must"),
            ],
            assumptions: [],
            components: [component],
            nets: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
        let url = root.appendingPathComponent("intent.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(intent).write(to: url)
        return url
    }

    private func writeCandidates(_ candidates: [ComponentCandidate], root: URL) throws -> URL {
        let url = root.appendingPathComponent("catalog-candidates.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidates).write(to: url)
        return url
    }

    private func writeAmpCandidates(from circuitIR: CircuitIR, root: URL) throws -> URL {
        try writeCandidates(circuitIR.components.map(ampCandidate), root: root)
    }

    private func ampCandidate(for component: CircuitComponent) -> ComponentCandidate {
        let mpn = component.manufacturerPartNumber ?? "\(component.refdes)-MPN"
        return ComponentCandidate(
            mpn: mpn,
            manufacturer: "fixture",
            normalizedCategory: component.role.replacingOccurrences(of: " ", with: "_").lowercased(),
            value: nil,
            package: component.selectedFootprint ?? "library_package",
            ratings: ["fixture_rating": "present"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: "fixture",
                    mpn: mpn,
                    url: "https://example.invalid/\(mpn).pdf",
                    localPath: nil,
                    sha256: nil,
                    providerID: "fixture",
                    retrievedAt: "2026-05-30T18:00:00Z",
                    license: "fixture",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/\(mpn)",
                    localPath: nil,
                    retrievedAt: "2026-05-30T18:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["target_refdes": component.refdes, "mpn": mpn],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
    }

    private func writeCircuitIR(_ components: [CircuitComponent], root: URL) throws -> URL {
        let circuitIR = CircuitIR(
            designId: "amp-low-voltage",
            boardId: "amp_low_voltage_audio",
            components: components,
            nets: [],
            constraints: [],
            verificationScenarios: []
        )
        let url = root.appendingPathComponent("circuit-ir.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(circuitIR).write(to: url)
        return url
    }

    private func circuitComponent(
        refdes: String,
        role: String,
        selectedSymbol: String,
        selectedFootprint: String? = nil,
        pins: [String],
        constraints: [String: String] = [:]
    ) -> CircuitComponent {
        CircuitComponent(
            refdes: refdes,
            role: role,
            selectedSymbol: selectedSymbol,
            selectedFootprint: selectedFootprint,
            manufacturerPartNumber: nil,
            sourceEvidence: [SourceEvidence(kind: "design_intent_component", reference: "FILTER1")],
            pins: pins.map {
                CircuitPin(
                    componentRefdes: refdes,
                    pinNumber: $0,
                    canonicalName: $0,
                    electricalType: "passive",
                    symbolPin: $0,
                    footprintPad: nil
                )
            },
            constraints: constraints
        )
    }

    private func catalogCandidate(
        refdes: String,
        mpn: String,
        manufacturer: String = "fixture",
        category: String,
        value: String,
        package: String,
        ratings: [String: String]
    ) -> ComponentCandidate {
        let hydratedRatings = ratings.merging(["target_refdes": refdes]) { existing, _ in existing }
        return ComponentCandidate(
            mpn: mpn,
            manufacturer: manufacturer,
            normalizedCategory: category,
            value: value,
            package: package,
            ratings: hydratedRatings,
            lifecycleState: "Active",
            availabilitySummary: "100 In Stock",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: manufacturer,
                    mpn: mpn,
                    url: "https://example.invalid/\(mpn).pdf",
                    localPath: nil,
                    sha256: nil,
                    providerID: "fixture",
                    retrievedAt: "2026-06-02T12:00:00Z",
                    license: "fixture",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/\(mpn)",
                    localPath: nil,
                    retrievedAt: "2026-06-02T12:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: hydratedRatings.merging(["package": package]) { existing, _ in existing },
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
    }

    private func validCandidate(mpn: String, category: String = "power_transistor") -> ComponentCandidate {
        ComponentCandidate(
            mpn: mpn,
            manufacturer: "onsemi",
            normalizedCategory: category,
            value: nil,
            package: "TO-3",
            ratings: ["voltage_v": "140", "current_a": "20", "power_w": "250"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: "onsemi",
                    mpn: mpn,
                    url: "https://example.invalid/\(mpn).pdf",
                    localPath: nil,
                    sha256: nil,
                    providerID: "fixture",
                    retrievedAt: "2026-05-30T15:00:00Z",
                    license: "fixture",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/\(mpn)",
                    localPath: nil,
                    retrievedAt: "2026-05-30T15:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["mpn": mpn, "package": "TO-3"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: [
                FootprintCandidate(
                    library: "Package_TO_SOT_THT",
                    name: "TO-3",
                    packageCompatibilityEvidence: "fixture package match",
                    pinPadMap: ["B": "1", "C": "2"],
                    sourceProviderID: "fixture",
                    sourcePath: "Package_TO_SOT_THT.pretty/TO-3.kicad_mod",
                    threeDModel: nil
                ),
            ]
        )
    }

    private func writeMouserFixture(root: URL) throws -> URL {
        let url = root.appendingPathComponent("mouser-fixture.json")
        try """
        {"SearchResults":{"Parts":[{"Manufacturer":"Yageo","ManufacturerPartNumber":"RC0603FR-0710KL","Description":"RES 10K OHM 1% 1/10W 0603","Category":"Resistors","DataSheetUrl":"https://example.invalid/rc0603.pdf","ProductDetailUrl":"https://mouser.example/RC0603","LifecycleStatus":"Active","Availability":"9,000 In Stock","ProductAttributes":[{"AttributeName":"Package / Case","AttributeValue":"0603"},{"AttributeName":"Resistance","AttributeValue":"10 kOhms"},{"AttributeName":"Power Rating","AttributeValue":"0.1 W"}]}]}}
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeNexarFixture(root: URL) throws -> URL {
        let url = root.appendingPathComponent("nexar-fixture.json")
        try """
        {"data":{"supSearchMpn":{"results":[{"description":"NPN power transistor","part":{"name":"MJ15003G","mpn":"MJ15003G","shortDescription":"NPN transistor","totalAvail":128,"manufacturer":{"name":"onsemi","homepageUrl":"https://www.onsemi.com"},"category":{"name":"Bipolar Transistors"},"specs":[{"attribute":{"name":"Package / Case","shortname":"Package / Case"},"displayValue":"TO-3"},{"attribute":{"name":"Power - Max","shortname":"Power - Max"},"displayValue":"250 W"},{"attribute":{"name":"Voltage - Collector Emitter Breakdown (Max)","shortname":"Vce"},"displayValue":"140 V"},{"attribute":{"name":"Current - Collector (Ic) (Max)","shortname":"Ic"},"displayValue":"20 A"},{"attribute":{"name":"Transistor Polarity","shortname":"Polarity"},"displayValue":"NPN"},{"attribute":{"name":"Lifecycle Status","shortname":"Lifecycle Status"},"displayValue":"Active"}],"bestDatasheet":{"url":"https://example.invalid/mj15003g.pdf"},"sellers":[{"company":{"name":"Digi-Key"},"offers":[{"inventoryLevel":50}]},{"company":{"name":"Mouser"},"offers":[{"inventoryLevel":78}]}]}}]}}}
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeVendorFeedCSV(root: URL) throws -> URL {
        let url = root.appendingPathComponent("vendor-feed.csv")
        try """
        Manufacturer,MPN,Description,Category,Package,Voltage,Current,Power,Datasheet URL,Product URL,Availability,Distributor,MOQ,Packaging,Lead Time,Lifecycle
        onsemi,MJ15003G,"NPN Bipolar Transistor 140V 20A 250W TO-3",Bipolar Transistors,TO-3,140 V,20 A,250 W,https://example.invalid/mj15003g.pdf,https://vendor.example/MJ15003G,50,Digi-Key,1,Tube,0 weeks,Active
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeSymbols(root: URL) throws -> URL {
        let url = root.appendingPathComponent("symbols.json")
        let symbols = [
            KiCadSymbolDefinition(
                name: "Device:R",
                pins: [
                    KiCadSymbolPin(number: "1", name: "1", electricalType: "passive"),
                    KiCadSymbolPin(number: "2", name: "2", electricalType: "passive"),
                ]
            ),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(symbols).write(to: url)
        return url
    }

    private func writeSymbols(from circuitIR: CircuitIR, root: URL) throws -> URL {
        let url = root.appendingPathComponent("amp-symbols.json")
        let symbols = circuitIR.components.map { component in
            KiCadSymbolDefinition(
                name: component.selectedSymbol,
                pins: component.pins.map {
                    KiCadSymbolPin(number: $0.pinNumber, name: $0.symbolPin, electricalType: $0.electricalType)
                }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(symbols).write(to: url)
        return url
    }

    private func writeFootprints(root: URL) throws -> URL {
        let url = root.appendingPathComponent("footprints.json")
        let footprints = [
            KiCadFootprintDefinition(
                name: "Resistor_SMD:R_0603_1608Metric",
                pads: [
                    KiCadFootprintPad(number: "1", name: "1"),
                    KiCadFootprintPad(number: "2", name: "2"),
                ]
            ),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(footprints).write(to: url)
        return url
    }

    private func writeFootprints(from circuitIR: CircuitIR, root: URL) throws -> URL {
        let url = root.appendingPathComponent("amp-footprints.json")
        let footprints = circuitIR.components.compactMap { component -> KiCadFootprintDefinition? in
            guard let footprint = component.selectedFootprint else { return nil }
            return KiCadFootprintDefinition(
                name: footprint,
                pads: component.pins.compactMap {
                    guard let pad = $0.footprintPad else { return nil }
                    return KiCadFootprintPad(number: pad, name: $0.symbolPin)
                }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(footprints).write(to: url)
        return url
    }

    private func writeAmpDemoFootprints(root: URL) throws -> URL {
        let url = root.appendingPathComponent("ampdemo-footprints.json")
        let footprints = [
            KiCadFootprintDefinition(name: "TerminalBlock_Phoenix:TerminalBlock_Phoenix_MKDS-1,5-2-5.08_1x02_P5.08mm_Horizontal", pads: numberedPads(["1", "2"])),
            KiCadFootprintDefinition(name: "Diode_THT:Diode_Bridge_Vishay_GBU", pads: namedPads(["AC1", "AC2", "PLUS", "MINUS"])),
            KiCadFootprintDefinition(name: "Capacitor_THT:CP_Radial_D18.0mm_P7.50mm", pads: numberedPads(["1", "2"])),
            KiCadFootprintDefinition(name: "Connector_Audio:Jack_6.35mm_Neutrik_NMJ6HFD2_Horizontal", pads: numberedPads(["1", "2"])),
            KiCadFootprintDefinition(name: "Package_TO_SOT_THT:TO-92_Inline", pads: namedPads(["B", "C", "E"])),
            KiCadFootprintDefinition(name: "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal", pads: numberedPads(["1", "2"])),
            KiCadFootprintDefinition(name: "Capacitor_THT:C_Rect_L7.2mm_W3.5mm_P5.00mm", pads: numberedPads(["1", "2"])),
            KiCadFootprintDefinition(name: "Potentiometer_THT:Potentiometer_Bourns_PTV09A-1_Single_Vertical", pads: namedPads(["A", "W", "B"])),
            KiCadFootprintDefinition(name: "Package_TO_SOT_THT:TO-220-3_Vertical", pads: namedPads(["B", "C", "E"])),
            KiCadFootprintDefinition(name: "Package_TO_SOT_THT:TO-3", pads: namedPads(["B", "C", "E"])),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(footprints).write(to: url)
        return url
    }

    private func numberedPads(_ numbers: [String]) -> [KiCadFootprintPad] {
        numbers.map { KiCadFootprintPad(number: $0, name: $0) }
    }

    private func namedPads(_ names: [String]) -> [KiCadFootprintPad] {
        names.enumerated().map { index, name in
            KiCadFootprintPad(number: "\(index + 1)", name: name)
        }
    }

    private func writeKiCadSymbolTree(root: URL, directoryName: String = "kicad-symbols") throws -> URL {
        let symbolRoot = root.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: symbolRoot, withIntermediateDirectories: true)
        try """
        (kicad_symbol_lib
          (version 20250114)
          (symbol "R"
            (pin passive line (at 0 0 0) (length 2.54) (name "1") (number "1"))
            (pin passive line (at 5.08 0 180) (length 2.54) (name "2") (number "2"))))
        """.write(to: symbolRoot.appendingPathComponent("Device.kicad_sym"), atomically: true, encoding: .utf8)
        return symbolRoot
    }

    private func writeKiCadFootprintTree(root: URL, directoryName: String = "kicad-footprints") throws -> URL {
        let footprintRoot = root.appendingPathComponent(directoryName, isDirectory: true)
        let libraryRoot = footprintRoot.appendingPathComponent("Resistor_SMD.pretty", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try """
        (footprint "R_0603_1608Metric"
          (pad "1" smd roundrect (at -0.8 0) (size 0.8 0.95) (layers "F.Cu"))
          (pad "2" smd roundrect (at 0.8 0) (size 0.8 0.95) (layers "F.Cu")))
        """.write(to: libraryRoot.appendingPathComponent("R_0603_1608Metric.kicad_mod"), atomically: true, encoding: .utf8)
        return footprintRoot
    }

    private func send(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_select_components"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendCircuitIR(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_generate_circuit_ir"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendCatalogImport(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "catalog.import_vendor_feed"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendFootprints(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_assign_footprints"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendCompile(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_compile_project"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendERC(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_run_erc"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func sendDRC(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_run_drc"),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-evidence-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
