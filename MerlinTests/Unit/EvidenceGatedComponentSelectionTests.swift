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

        XCTAssertEqual(response.status, .ok)
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

    func testMultipleValidCandidatesAreAmbiguous() async throws {
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
        XCTAssertEqual(matrix.decisions.map(\.status), [.ambiguous])
        XCTAssertEqual(matrix.decisions.first?.candidateSet.count, 2)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
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

        XCTAssertEqual(response.status, .ok)
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

    private func component(refdes: String, role: String) -> ComponentIntent {
        ComponentIntent(refdes: refdes, role: role, constraints: ["implementation": "discrete"])
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
        pins: [String]
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
            }
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
