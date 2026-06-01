import XCTest
@testable import Merlin

final class AmpLowVoltageFixtureTests: XCTestCase {
    func testLowVoltageDesignIntentFixtureCapturesRequiredScopeAndDecisions() throws {
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let text = ([intent.title] + intent.requirements.map(\.text) + intent.assumptions.map(\.text)).joined(separator: " ").lowercased()

        XCTAssertEqual(intent.designId, "amp_low_voltage_audio")
        XCTAssertEqual(intent.approval.status, .approved)
        XCTAssertTrue(intent.boards.contains { $0.id == "amp_low_voltage_audio" && $0.safetyDomain == "isolated_secondary" })
        for required in ["preamp", "3-band tone", "sweepable boost/cut", "driver", "output stage", "speaker output", "low-voltage rail", "thermal"] {
            XCTAssertTrue(text.contains(required), "Missing required scope text: \(required)")
        }
        XCTAssertFalse(intent.unresolvedDecisions.isEmpty)
        XCTAssertTrue(intent.unresolvedDecisions.allSatisfy { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testCircuitIRFixtureUsesDiscreteEvidenceBackedComponentsForRequiredBlocks() throws {
        let circuitIR: CircuitIR = try loadFixture("circuit_ir.json")
        let roles = circuitIR.components.map(\.role).joined(separator: " ").lowercased()

        XCTAssertEqual(circuitIR.boardId, "amp_low_voltage_audio")
        for required in ["input jack", "preamp", "bass", "mid", "treble", "boost/cut", "driver", "output transistor", "speaker output", "rail reservoir"] {
            XCTAssertTrue(roles.contains(required), "Missing required circuit role: \(required)")
        }
        XCTAssertGreaterThanOrEqual(circuitIR.components.count, 20)
        XCTAssertTrue(circuitIR.components.allSatisfy { !$0.pins.isEmpty && !$0.sourceEvidence.isEmpty })
        XCTAssertTrue(circuitIR.constraints.contains { $0.kind == "thermal" && $0.target == "QOUT1" })
    }

    func testFixturePassesGenericResolverMaterializerERCAndSchematicVerification() throws {
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("circuit_ir.json")
        let schemaResult = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: intent,
            circuitIR: circuitIR
        )
        XCTAssertTrue(schemaResult.isValid, schemaResult.issues.map(\.message).joined(separator: "\n"))

        let resolver = KiCadLibraryPinResolver(
            symbols: circuitIR.components.map(symbolDefinition),
            footprints: circuitIR.components.compactMap(footprintDefinition)
        )
        for component in circuitIR.components {
            let resolution = resolver.resolve(component: component, pcbBound: true)
            XCTAssertTrue(resolution.isResolved, "\(component.refdes): \(resolution.issues)")
        }

        let outputDirectory = temporaryDirectory("amp-low-voltage-fixture")
        let materialized = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputDirectory
        )
        let schematic = try KiCadSchematicParser().parse(String(contentsOf: materialized.schematicURL, encoding: .utf8))
        let parity = CircuitIRSchematicParityChecker().check(circuitIR: circuitIR, schematic: schematic)
        XCTAssertTrue(parity.isValid, parity.issues.map(\.message).joined(separator: "\n"))

        let ercResult = ERCRepairLoop().run(
            initialSchematic: schematic,
            circuitIR: circuitIR,
            ercReports: [KiCadERCReport(violations: [])],
            resolverEvidence: circuitIR.components.map { resolver.resolve(component: $0, pcbBound: true) }
        )
        XCTAssertEqual(ercResult.status, .verified)

        let verification = SchematicVerificationGate().evaluate(SchematicVerificationEvidence(
            approvedDesignIntent: intent.approval.status == .approved,
            circuitIRValidationPassed: schemaResult.isValid,
            kicadProjectPath: materialized.projectURL.path,
            kicadSchematicPath: materialized.schematicURL.path,
            ercReportPath: outputDirectory.appendingPathComponent("erc-report.json").path,
            hasSchematicVerificationReport: true,
            blockingERCViolations: [],
            repairLoopStatus: ercResult.status
        ))
        XCTAssertEqual(verification.status, .schematicVerified)
    }

    func testFixtureRealKiCadERCGateUsesGeneratedSchematicEvidence() throws {
        let kicadCLI = try findKiCadCLIOrSkip()
        let intent: DesignIntent = try loadFixture("design_intent.json")
        let circuitIR: CircuitIR = try loadFixture("circuit_ir.json")
        let schemaResult = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: intent,
            circuitIR: circuitIR
        )
        XCTAssertTrue(schemaResult.isValid, schemaResult.issues.map(\.message).joined(separator: "\n"))

        let outputDirectory = temporaryDirectory("amp-low-voltage-real-erc")
        let materialized = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputDirectory
        )
        let reportURL = outputDirectory.appendingPathComponent("erc-report.json")
        let result = try runKiCad(kicadCLI, [
            "sch", "erc",
            "--format", "json",
            "--output", reportURL.path,
            materialized.schematicURL.path,
        ])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: reportURL.path),
            "kicad-cli did not produce an ERC report. Exit \(result.status): \(result.output)"
        )

        let report = try KiCadERCParser().parse(jsonData: Data(contentsOf: reportURL))
        let codes = Set(report.violations.map(\.code))
        XCTAssertFalse(codes.contains("wire_dangling"), result.output)
        XCTAssertFalse(codes.contains("label_dangling"), result.output)
        XCTAssertFalse(codes.contains("unconnected_wire_endpoint"), result.output)

        let resolver = KiCadLibraryPinResolver(
            symbols: circuitIR.components.map(symbolDefinition),
            footprints: circuitIR.components.compactMap(footprintDefinition)
        )
        let repairResult = ERCRepairLoop().run(
            initialSchematic: try KiCadSchematicParser().parse(String(contentsOf: materialized.schematicURL, encoding: .utf8)),
            circuitIR: circuitIR,
            ercReports: [report],
            resolverEvidence: circuitIR.components.map { resolver.resolve(component: $0, pcbBound: true) }
        )
        let verification = SchematicVerificationGate().evaluate(SchematicVerificationEvidence(
            approvedDesignIntent: intent.approval.status == .approved,
            circuitIRValidationPassed: schemaResult.isValid,
            kicadProjectPath: materialized.projectURL.path,
            kicadSchematicPath: materialized.schematicURL.path,
            ercReportPath: reportURL.path,
            hasSchematicVerificationReport: true,
            blockingERCViolations: report.blockingViolations,
            repairLoopStatus: repairResult.status
        ))
        if report.blockingViolations.isEmpty {
            XCTAssertEqual(verification.status, .schematicVerified)
        } else {
            XCTAssertEqual(verification.status, .blocked)
        }
    }

    func testMainsPowerSupplyFixtureIsSeparateHighStakesStub() throws {
        let intent: DesignIntent = try loadFixture("mains_power_supply_design_intent.json")
        let text = intent.requirements.map(\.text).joined(separator: " ").lowercased()

        XCTAssertEqual(intent.designId, "amp_mains_power_supply")
        XCTAssertEqual(intent.approval.status, .draft)
        XCTAssertTrue(intent.boards.contains { $0.id == "amp_mains_power_supply" })
        XCTAssertTrue(text.contains("mains inlet"))
        XCTAssertTrue(text.contains("protective earth"))
        XCTAssertTrue(intent.unresolvedDecisions.contains { $0.blocking })
    }

    func testNoNamedAmpGeneratorCodePathIsUsed() throws {
        for path in [
            "Merlin/Plugins/ElectronicsRuntimePlugin.swift",
            "Merlin/Electronics/CircuitIRKiCadSchematicMaterializer.swift",
            "Merlin/Electronics/ERCRepairLoop.swift",
        ] {
            let source = try repoText(path)
            XCTAssertFalse(source.contains("amp_low_voltage_audio"), "\(path) must not special-case the amp fixture")
            XCTAssertFalse(source.contains("amp_mains_power_supply"), "\(path) must not special-case the mains fixture")
        }
    }

    private func loadFixture<T: Decodable>(_ name: String) throws -> T {
        let url = repoRoot()
            .appendingPathComponent("plugins/electronics/fixtures/amp_low_voltage_audio")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func symbolDefinition(for component: CircuitComponent) -> KiCadSymbolDefinition {
        KiCadSymbolDefinition(
            name: component.selectedSymbol,
            pins: component.pins.map {
                KiCadSymbolPin(number: $0.pinNumber, name: $0.symbolPin, electricalType: $0.electricalType)
            }
        )
    }

    private func footprintDefinition(for component: CircuitComponent) -> KiCadFootprintDefinition? {
        guard let footprint = component.selectedFootprint else { return nil }
        return KiCadFootprintDefinition(
            name: footprint,
            pads: component.pins.compactMap { pin in
                guard let pad = pin.footprintPad else { return nil }
                return KiCadFootprintPad(number: pad, name: nil)
            }
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MerlinTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func repoText(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func findKiCadCLIOrSkip() throws -> URL {
        let candidates = [
            "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
            "/Applications/KiCad.app/Contents/MacOS/kicad-cli",
            "/opt/homebrew/bin/kicad-cli",
            "/usr/local/bin/kicad-cli",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw XCTSkip("kicad-cli is not installed")
    }

    private func runKiCad(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
