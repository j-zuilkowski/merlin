import XCTest
@testable import Merlin

final class ComponentCatalogContractsTests: XCTestCase {
    func testComponentCatalogContractsRoundTrip() throws {
        let matrix = ComponentMatrix(
            designId: "amp-low-voltage",
            decisions: [
                PartSelectionDecision(
                    refdes: "QOUT1",
                    status: .selected,
                    selectedCandidate: validCandidate(),
                    candidateSet: [validCandidate()],
                    rationale: "fixture evidence satisfies required ratings",
                    evidenceReferences: [validEvidence()],
                    unresolvedDecisions: []
                ),
            ],
            warnings: [],
            providers: ["fixture"],
            cacheMetadata: ["ttl_seconds": "0"]
        )

        XCTAssertRoundTrips(ComponentSearchRequest(
            refdes: "QOUT1",
            role: "single-ended Class-A output transistor",
            constraints: ["minimum_voltage_v": "140", "minimum_power_w": "250"],
            requiredEvidenceTypes: ["datasheet", "package", "ratings"],
            preferredVendors: ["Digi-Key", "Mouser"],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        ))
        XCTAssertRoundTrips(validCandidate())
        XCTAssertRoundTrips(validEvidence())
        XCTAssertRoundTrips(validDatasheet())
        XCTAssertRoundTrips(validFootprint())
        XCTAssertRoundTrips(matrix)
    }

    func testCandidateWithoutRequiredEvidenceIsRejected() {
        let candidate = ComponentCandidate(
            mpn: "",
            manufacturer: "",
            normalizedCategory: "transistor",
            value: nil,
            package: "",
            ratings: [:],
            lifecycleState: "",
            availabilitySummary: "",
            datasheets: [],
            evidence: [],
            footprintCandidates: []
        )

        let result = ComponentCatalogValidator().validate(candidate)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "MPN_REQUIRED"))
        XCTAssertTrue(result.contains(code: "MANUFACTURER_REQUIRED"))
        XCTAssertTrue(result.contains(code: "PACKAGE_REQUIRED"))
        XCTAssertTrue(result.contains(code: "RATINGS_REQUIRED"))
        XCTAssertTrue(result.contains(code: "DATASHEET_REQUIRED"))
        XCTAssertTrue(result.contains(code: "PROVENANCE_REQUIRED"))
    }

    func testCommodityPassiveWithVendorProductEvidenceDoesNotRequireDatasheetURL() {
        let candidate = ComponentCandidate(
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
        )

        let result = ComponentCatalogValidator().validate(candidate)

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.contains(code: "DATASHEET_REQUIRED"))
    }

    func testActiveComponentStillRequiresDatasheetURL() {
        var candidate = validCandidate()
        candidate.datasheets = []

        let result = ComponentCatalogValidator().validate(candidate)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "DATASHEET_REQUIRED"))
    }

    func testStaticFixtureCatalogProviderReturnsCandidatesOffline() async throws {
        let provider = StaticFixtureCatalogProvider(candidates: [validCandidate()])

        let candidates = try await provider.search(ComponentSearchRequest(
            refdes: "QOUT1",
            role: "Class-A output transistor",
            constraints: ["mpn": "MJ15003G"],
            requiredEvidenceTypes: ["datasheet"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "active"
        ))

        XCTAssertEqual(provider.providerID, "fixture")
        XCTAssertEqual(candidates.map(\.mpn), ["MJ15003G"])
        XCTAssertEqual(candidates.first?.evidence.first?.providerID, "fixture")
    }

    func testKiCadLibraryCatalogProviderExposesSymbolAndFootprintEvidence() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [
                KiCadSymbolDefinition(
                    name: "Device:Q_NPN_BCE",
                    pins: [
                        KiCadSymbolPin(number: "1", name: "B", electricalType: "input"),
                        KiCadSymbolPin(number: "2", name: "C", electricalType: "power"),
                    ]
                ),
            ],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    pads: [
                        KiCadFootprintPad(number: "1", name: "B"),
                        KiCadFootprintPad(number: "2", name: "C"),
                    ]
                ),
            ]
        )

        let candidates = try await provider.search(ComponentSearchRequest(
            refdes: "QOUT1",
            role: "Class-A output transistor",
            constraints: [
                "symbol": "Device:Q_NPN_BCE",
                "footprint": "Package_TO_SOT_THT:TO-3P-3_Vertical",
            ],
            requiredEvidenceTypes: ["symbol", "footprint"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "draft"
        ))

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(provider.providerID, "kicad_local")
        XCTAssertEqual(candidate.evidence.map(\.providerID), ["kicad_local", "kicad_local"])
        XCTAssertEqual(candidate.footprintCandidates.first?.pinPadMap["B"], "1")
        XCTAssertTrue(candidate.evidence.contains { $0.extractedParameters["symbol"] == "Device:Q_NPN_BCE" })
    }

    func testKiCadLibraryCatalogProviderRequiresConnectorSubtypeMatch() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Connector_Coaxial:BNC_PanelMountable_Vertical",
                    pads: numberedPads(["1", "2"])
                ),
                KiCadFootprintDefinition(
                    name: "Connector_DIN:DIN41612_B_1x32_Female_Vertical_THT",
                    pads: numberedPads(["1", "2", "3", "4"])
                ),
            ]
        )

        let candidates = try await provider.search(ComponentSearchRequest(
            refdes: "JIN",
            role: "high impedance guitar input connector",
            constraints: [
                "component_category": "phone_audio_jack",
                "package": "Free Hanging (In-Line)",
                "positions": "2",
            ],
            requiredEvidenceTypes: ["footprint"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "library_asset"
        ))

        XCTAssertTrue(candidates.flatMap(\.footprintCandidates).isEmpty)
    }

    func testKiCadLibraryCatalogProviderPrefersTerminalBlockSubtypeForSecondaryInput() async throws {
        let provider = KiCadLibraryCatalogProvider(
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Connector_Coaxial:BNC_PanelMountable_Vertical",
                    pads: numberedPads(["1", "2"])
                ),
                KiCadFootprintDefinition(
                    name: "Connector_Phoenix_GMSTB:PhoenixContact_GMSTBA_2,5_2-G_1x02_P7.50mm_Horizontal",
                    pads: numberedPads(["1", "2"])
                ),
            ]
        )

        let candidates = try await provider.search(ComponentSearchRequest(
            refdes: "JSEC",
            role: "isolated transformer secondary input connector",
            constraints: [
                "component_category": "terminal_block",
                "package": "Panel Mount, Through Hole",
                "positions": "2",
            ],
            requiredEvidenceTypes: ["footprint"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "library_asset"
        ))

        let footprints = candidates.flatMap(\.footprintCandidates)
        XCTAssertEqual(footprints.map(\.sourcePath), [
            "Connector_Phoenix_GMSTB:PhoenixContact_GMSTBA_2,5_2-G_1x02_P7.50mm_Horizontal",
        ])
    }

    func testKiCadLibraryCatalogExtractorReadsLocalSymbolAndFootprintTrees() throws {
        let root = try temporaryDirectory()
        let symbolRoot = root.appendingPathComponent("symbols", isDirectory: true)
        let footprintRoot = root.appendingPathComponent("footprints", isDirectory: true)
        try FileManager.default.createDirectory(at: symbolRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: footprintRoot.appendingPathComponent("Resistor_SMD.pretty", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        (kicad_symbol_lib
          (version 20250114)
          (symbol "R"
            (pin passive line (at 0 0 0) (length 2.54) (name "1") (number "1"))
            (pin passive line (at 5.08 0 180) (length 2.54) (name "2") (number "2"))))
        """.write(to: symbolRoot.appendingPathComponent("Device.kicad_sym"), atomically: true, encoding: .utf8)
        try """
        (footprint "R_0603_1608Metric"
          (pad "1" smd roundrect (at -0.8 0) (size 0.8 0.95) (layers "F.Cu"))
          (pad "2" smd roundrect (at 0.8 0) (size 0.8 0.95) (layers "F.Cu")))
        """.write(
            to: footprintRoot
                .appendingPathComponent("Resistor_SMD.pretty", isDirectory: true)
                .appendingPathComponent("R_0603_1608Metric.kicad_mod"),
            atomically: true,
            encoding: .utf8
        )

        let catalog = try KiCadLibraryCatalogExtractor().extract(symbolRoot: symbolRoot, footprintRoot: footprintRoot)

        XCTAssertEqual(catalog.symbols.map(\.name), ["Device:R"])
        XCTAssertEqual(catalog.symbols.first?.pins.map(\.number), ["1", "2"])
        XCTAssertEqual(catalog.footprints.map(\.name), ["Resistor_SMD:R_0603_1608Metric"])
        XCTAssertEqual(catalog.footprints.first?.pads.map(\.number), ["1", "2"])
    }

    func testKiCadLibraryCatalogCacheHonorsTTL() throws {
        let root = try temporaryDirectory()
        let cacheURL = root.appendingPathComponent("catalog-cache", isDirectory: true)
        let catalog = KiCadLocalLibraryCatalog(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            symbols: [KiCadSymbolDefinition(name: "Device:R", pins: [])],
            footprints: [KiCadFootprintDefinition(name: "Resistor_SMD:R_0603_1608Metric", pads: [])]
        )

        try KiCadLibraryCatalogCache().write(catalog, to: cacheURL)

        let fresh = try KiCadLibraryCatalogCache().load(from: cacheURL, maxAgeSeconds: 60, now: Date(timeIntervalSince1970: 1_030))
        XCTAssertEqual(fresh?.symbols.map(\.name), ["Device:R"])

        let stale = try KiCadLibraryCatalogCache().load(from: cacheURL, maxAgeSeconds: 60, now: Date(timeIntervalSince1970: 1_061))
        XCTAssertNil(stale)
    }

    func testKiCadLibraryCatalogCacheRejectsOldExtractWithoutFootprintSourcePaths() throws {
        let root = try temporaryDirectory()
        let cacheURL = root.appendingPathComponent("catalog-cache", isDirectory: true)
        let catalog = KiCadLocalLibraryCatalog(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            symbols: [],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Resistor_SMD:R_0603_1608Metric",
                    pads: [
                        KiCadFootprintPad(number: "1", name: nil),
                        KiCadFootprintPad(number: "2", name: nil),
                    ]
                ),
            ]
        )

        try KiCadLibraryCatalogCache().write(catalog, to: cacheURL)

        let loaded = try KiCadLibraryCatalogCache().load(
            from: cacheURL,
            maxAgeSeconds: 60,
            now: Date(timeIntervalSince1970: 1_030)
        )
        XCTAssertNil(loaded)
    }

    func testKiCadLibraryRootDiscoveryFindsConfiguredInstallLayout() throws {
        let root = try temporaryDirectory()
        let installRoot = root.appendingPathComponent("KiCad.app/Contents/SharedSupport/kicad", isDirectory: true)
        let symbolRoot = installRoot.appendingPathComponent("symbols", isDirectory: true)
        let footprintRoot = installRoot.appendingPathComponent("footprints", isDirectory: true)
        try FileManager.default.createDirectory(at: symbolRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: footprintRoot, withIntermediateDirectories: true)

        let roots = try XCTUnwrap(KiCadLibraryRootDiscovery().discover(searchRoots: [root]))

        XCTAssertEqual(roots.symbolRoot.path, symbolRoot.path)
        XCTAssertEqual(roots.footprintRoot.path, footprintRoot.path)
    }

    func testKiCadLibraryRootDiscoveryFindsAppSharedSupportLayout() throws {
        let root = try temporaryDirectory()
        let installRoot = root.appendingPathComponent("KiCad.app/Contents/SharedSupport", isDirectory: true)
        let symbolRoot = installRoot.appendingPathComponent("symbols", isDirectory: true)
        let footprintRoot = installRoot.appendingPathComponent("footprints", isDirectory: true)
        try FileManager.default.createDirectory(at: symbolRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: footprintRoot, withIntermediateDirectories: true)

        let roots = try XCTUnwrap(KiCadLibraryRootDiscovery().discover(searchRoots: [root]))

        XCTAssertEqual(roots.symbolRoot.path, symbolRoot.path)
        XCTAssertEqual(roots.footprintRoot.path, footprintRoot.path)
    }

    func testKiCadLibraryRootCacheHonorsTTL() throws {
        let root = try temporaryDirectory()
        let cacheURL = root.appendingPathComponent("root-cache", isDirectory: true)
        let symbolRoot = root.appendingPathComponent("kicad/symbols", isDirectory: true)
        let footprintRoot = root.appendingPathComponent("kicad/footprints", isDirectory: true)
        try FileManager.default.createDirectory(at: symbolRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: footprintRoot, withIntermediateDirectories: true)
        let roots = KiCadLibraryRoots(
            generatedAt: Date(timeIntervalSince1970: 2_000),
            symbolRoot: symbolRoot,
            footprintRoot: footprintRoot
        )

        try KiCadLibraryRootCache().write(roots, to: cacheURL)

        let fresh = try KiCadLibraryRootCache().load(from: cacheURL, maxAgeSeconds: 60, now: Date(timeIntervalSince1970: 2_010))
        XCTAssertEqual(fresh?.symbolRoot.path, symbolRoot.path)

        let stale = try KiCadLibraryRootCache().load(from: cacheURL, maxAgeSeconds: 60, now: Date(timeIntervalSince1970: 2_061))
        XCTAssertNil(stale)
    }

    func testPluginOwnedSchemasDocumentCatalogContracts() throws {
        for relativePath in [
            "plugins/electronics/schemas/component_catalog.schema.json",
            "plugins/electronics/schemas/component_matrix.schema.json",
        ] {
            let data = try Data(contentsOf: repoRoot().appendingPathComponent(relativePath))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        }
    }

    private func validCandidate() -> ComponentCandidate {
        ComponentCandidate(
            mpn: "MJ15003G",
            manufacturer: "onsemi",
            normalizedCategory: "bipolar_power_transistor",
            value: nil,
            package: "TO-3",
            ratings: ["vceo_v": "140", "power_w": "250", "current_a": "20"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [validDatasheet()],
            evidence: [validEvidence()],
            footprintCandidates: [validFootprint()]
        )
    }

    private func validEvidence() -> ComponentEvidence {
        ComponentEvidence(
            providerID: "fixture",
            sourceURL: "https://example.invalid/MJ15003G",
            localPath: nil,
            retrievedAt: "2026-05-30T14:00:00Z",
            cachePolicy: "fixture_no_cache",
            sha256: nil,
            extractedParameters: ["mpn": "MJ15003G", "package": "TO-3"],
            confidence: 1.0,
            warnings: []
        )
    }

    private func validDatasheet() -> DatasheetEvidence {
        DatasheetEvidence(
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            url: "https://example.invalid/MJ15003G-D.PDF",
            localPath: nil,
            sha256: nil,
            providerID: "fixture",
            retrievedAt: "2026-05-30T14:00:00Z",
            license: "fixture",
            citations: []
        )
    }

    private func validFootprint() -> FootprintCandidate {
        FootprintCandidate(
            library: "Package_TO_SOT_THT",
            name: "TO-3P-3_Vertical",
            packageCompatibilityEvidence: "fixture package match",
            pinPadMap: ["B": "1", "C": "2"],
            sourceProviderID: "fixture",
            sourcePath: "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod",
            threeDModel: nil
        )
    }

    private func numberedPads(_ numbers: [String]) -> [KiCadFootprintPad] {
        numbers.map { KiCadFootprintPad(number: $0, name: $0) }
    }

    private func XCTAssertRoundTrips<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            XCTAssertEqual(decoded, value, file: file, line: line)
        } catch {
            XCTFail("Round-trip failed: \(error)", file: file, line: line)
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-component-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
