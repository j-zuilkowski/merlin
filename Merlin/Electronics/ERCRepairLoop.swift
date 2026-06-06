import Foundation

enum KiCadERCSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case info

    var isBlocking: Bool {
        self == .error
    }
}

struct KiCadERCViolation: Codable, Sendable, Equatable {
    var id: String
    var code: String
    var severity: KiCadERCSeverity
    var message: String
    var refs: [String]

    var blocksSchematicVerification: Bool {
        severity.isBlocking || Self.schematicQualityBlockingCodes.contains(code)
    }

    private static let schematicQualityBlockingCodes: Set<String> = [
        "label_multiple_wires",
        "multiple_net_names",
    ]
}

struct KiCadERCReport: Codable, Sendable, Equatable {
    var violations: [KiCadERCViolation]

    var blockingViolations: [KiCadERCViolation] {
        violations.filter { $0.severity.isBlocking }
    }

    var schematicVerificationBlockingViolations: [KiCadERCViolation] {
        violations.filter(\.blocksSchematicVerification)
    }
}

enum KiCadERCParserError: Error, Equatable {
    case malformedReport
}

struct KiCadERCParser: Sendable {
    func parse(jsonData: Data) throws -> KiCadERCReport {
        let root = try JSONDecoder().decode(FlexibleERCReport.self, from: jsonData)
        return KiCadERCReport(violations: root.violations.map(\.violation))
    }
}

enum ERCRepairClass: String, Codable, Sendable, Equatable {
    case explicitNoConnect = "explicit_no_connect"
    case powerFlag = "power_flag"
    case netLabelMismatch = "net_label_mismatch"
    case knownEndpointConnection = "known_endpoint_connection"
    case pinMappingCorrection = "pin_mapping_correction"
    case generatedArtifactBug = "generated_artifact_bug"
    case incompleteCircuit = "incomplete_circuit"
}

struct ERCRepairPatch: Codable, Sendable, Equatable {
    var violationId: String
    var repairClass: ERCRepairClass
    var targetRef: String
    var action: String
    var details: String
}

struct ERCRepairPlan: Codable, Sendable, Equatable {
    var patches: [ERCRepairPatch]
    var unsupportedViolations: [KiCadERCViolation]

    var isRepairable: Bool {
        unsupportedViolations.isEmpty
    }
}

struct ERCRepairPlanner: Sendable {
    func planRepairs(
        report: KiCadERCReport,
        circuitIR: CircuitIR,
        resolverEvidence: [KiCadLibraryPinResolution]
    ) -> ERCRepairPlan {
        var patches: [ERCRepairPatch] = []
        var unsupported: [KiCadERCViolation] = []

        for violation in report.schematicVerificationBlockingViolations {
            guard let repairClass = classify(violation, circuitIR: circuitIR, resolverEvidence: resolverEvidence) else {
                unsupported.append(violation)
                continue
            }
            patches.append(ERCRepairPatch(
                violationId: violation.id,
                repairClass: repairClass,
                targetRef: violation.refs.first ?? "",
                action: actionName(for: repairClass),
                details: violation.message
            ))
        }

        return ERCRepairPlan(patches: patches, unsupportedViolations: unsupported)
    }

    private func classify(
        _ violation: KiCadERCViolation,
        circuitIR: CircuitIR,
        resolverEvidence: [KiCadLibraryPinResolution]
    ) -> ERCRepairClass? {
        switch violation.code {
        case "label_multiple_wires":
            return .generatedArtifactBug
        case "multiple_net_names":
            return .netLabelMismatch
        case "wire_dangling", "label_dangling", "unconnected_wire_endpoint":
            return .generatedArtifactBug
        case "pin_not_driven", "input_pin_not_driven":
            return .incompleteCircuit
        case "no_connect", "pin_not_connected", "unconnected_pin":
            return .explicitNoConnect
        case "power_flag_missing", "power_input_not_driven", "power_pin_not_driven":
            return .powerFlag
        case "net_label_mismatch", "label_mismatch":
            return .netLabelMismatch
        case "missing_connection", "endpoint_disconnected":
            return violation.refs.contains(where: { knownEndpoint($0, in: circuitIR) }) ? .knownEndpointConnection : nil
        case "pin_mapping_mismatch", "symbol_pin_mismatch":
            return violation.refs.contains(where: { provenPinMapping($0, resolverEvidence: resolverEvidence) }) ? .pinMappingCorrection : nil
        default:
            return nil
        }
    }

    private func knownEndpoint(_ ref: String, in circuitIR: CircuitIR) -> Bool {
        let parts = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        return circuitIR.components.contains { component in
            component.refdes == parts[0] && component.pins.contains { $0.pinNumber == parts[1] }
        }
    }

    private func provenPinMapping(
        _ ref: String,
        resolverEvidence: [KiCadLibraryPinResolution]
    ) -> Bool {
        let parts = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard let componentRef = parts.first else { return false }
        return resolverEvidence.contains { evidence in
            evidence.componentRefdes == componentRef && evidence.isResolved
        }
    }

    private func actionName(for repairClass: ERCRepairClass) -> String {
        switch repairClass {
        case .explicitNoConnect:
            return "add_no_connect"
        case .powerFlag:
            return "add_or_correct_power_flag"
        case .netLabelMismatch:
            return "correct_net_label"
        case .knownEndpointConnection:
            return "connect_known_endpoint"
        case .pinMappingCorrection:
            return "correct_pin_mapping_from_resolver"
        case .generatedArtifactBug:
            return "regenerate_schematic_from_pin_geometry"
        case .incompleteCircuit:
            return "complete_or_correct_circuit_ir"
        }
    }
}

enum ERCRepairLoopStatus: String, Codable, Sendable, Equatable {
    case verified
    case blocked
}

struct ERCRepairLoopResult: Sendable, Equatable {
    var status: ERCRepairLoopStatus
    var attempts: Int
    var finalSchematic: KiCadSchematicDocument
    var appliedPatches: [ERCRepairPatch]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct ERCRepairLoop: Sendable {
    var maxAttempts: Int = 3
    private let planner = ERCRepairPlanner()
    private let applier = ERCRepairPatchApplier()

    func run(
        initialSchematic: KiCadSchematicDocument,
        circuitIR: CircuitIR,
        ercReports: [KiCadERCReport],
        resolverEvidence: [KiCadLibraryPinResolution]
    ) -> ERCRepairLoopResult {
        var schematic = initialSchematic
        var attempts = 0
        var appliedPatches: [ERCRepairPatch] = []
        let reports = ercReports.isEmpty ? [KiCadERCReport(violations: [])] : ercReports

        for report in reports {
            if report.schematicVerificationBlockingViolations.isEmpty {
                return ERCRepairLoopResult(
                    status: .verified,
                    attempts: attempts,
                    finalSchematic: schematic,
                    appliedPatches: appliedPatches,
                    diagnostics: []
                )
            }
            if attempts >= maxAttempts {
                return blocked(
                    attempts: attempts,
                    schematic: schematic,
                    appliedPatches: appliedPatches,
                    code: "ERC_REPAIR_ATTEMPTS_EXHAUSTED",
                    message: "ERC repair attempts exhausted before KiCad reported a clean schematic."
                )
            }

            let plan = planner.planRepairs(
                report: report,
                circuitIR: circuitIR,
                resolverEvidence: resolverEvidence
            )
            guard plan.isRepairable else {
                return blocked(
                    attempts: attempts,
                    schematic: schematic,
                    appliedPatches: appliedPatches,
                    code: "UNSUPPORTED_ERC_VIOLATION",
                    message: plan.unsupportedViolations.map(\.code).joined(separator: ", ")
                )
            }

            attempts += 1
            appliedPatches.append(contentsOf: plan.patches)
            schematic = applier.apply(plan.patches, to: schematic)
        }

        return blocked(
            attempts: attempts,
            schematic: schematic,
            appliedPatches: appliedPatches,
            code: "ERC_REPAIR_ATTEMPTS_EXHAUSTED",
            message: "ERC repair loop ended without a clean ERC report."
        )
    }

    private func blocked(
        attempts: Int,
        schematic: KiCadSchematicDocument,
        appliedPatches: [ERCRepairPatch],
        code: String,
        message: String
    ) -> ERCRepairLoopResult {
        ERCRepairLoopResult(
            status: .blocked,
            attempts: attempts,
            finalSchematic: schematic,
            appliedPatches: appliedPatches,
            diagnostics: [ElectronicsSchemaIssue(code: code, message: message)]
        )
    }
}

struct ERCRepairPatchApplier: Sendable {
    private let pinGeometryResolver: KiCadSymbolGeometryResolver

    init(pinGeometryResolver: KiCadSymbolGeometryResolver = KiCadSymbolGeometryResolver()) {
        self.pinGeometryResolver = pinGeometryResolver
    }

    func apply(_ patches: [ERCRepairPatch], to schematic: KiCadSchematicDocument) -> KiCadSchematicDocument {
        var updated = schematic
        for patch in patches {
            if patch.repairClass == .explicitNoConnect,
               let point = noConnectPoint(for: patch, in: schematic) {
                updated.opaqueNodes.append(noConnectNode(at: point, patch: patch))
            }
        }
        return updated
    }

    private func noConnectPoint(
        for patch: ERCRepairPatch,
        in schematic: KiCadSchematicDocument
    ) -> KiCadSchematicDocument.Point? {
        guard let target = parseSymbolPinReference(patch.targetRef),
              let symbol = schematic.symbols.first(where: { $0.property(named: "Reference") == target.refdes }),
              let origin = symbol.at,
              let libraryID = symbol.property(named: "Symbol"),
              let geometry = pinGeometryResolver.resolve(libraryID: libraryID),
              let pin = geometry.pins.first(where: { $0.number == target.pinNumber || $0.name == target.pinNumber }) else {
            return nil
        }
        return KiCadSchematicDocument.Point(x: origin.x + pin.at.x, y: origin.y - pin.at.y)
    }

    private func parseSymbolPinReference(_ text: String) -> (refdes: String, pinNumber: String)? {
        let pattern = #"Symbol\s+([A-Za-z]+[A-Za-z0-9]*)\s+Pin\s+([A-Za-z0-9_+\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges >= 3,
              let refRange = Range(match.range(at: 1), in: text),
              let pinRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return (String(text[refRange]), String(text[pinRange]))
    }

    private func noConnectNode(at point: KiCadSchematicDocument.Point, patch: ERCRepairPatch) -> KiCadSExpression {
        .list([
            .atom("no_connect"),
            .list([.atom("at"), .atom(numberString(point.x)), .atom(numberString(point.y))]),
            .list([.atom("uuid"), .string(stableERCRepairUUID("no-connect", patch.violationId, patch.targetRef))]),
        ])
    }

    private func numberString(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        if rounded == floor(rounded) { return String(Int(rounded)) }
        var text = String(format: "%.6f", rounded)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private func stableERCRepairUUID(_ parts: String...) -> String {
        let input = parts.joined(separator: "|")
        let hash = input.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

enum SchematicVerificationEvidenceKey: String, Codable, Sendable, Equatable {
    case approvedDesignIntent = "approved_design_intent"
    case circuitIRValidation = "circuit_ir_validation"
    case kicadProject = "kicad_project"
    case kicadSchematic = "kicad_schematic"
    case ercReport = "erc_report"
    case schematicVerificationReport = "schematic_verification_report"
}

enum SchematicVerificationStatus: String, Codable, Sendable, Equatable {
    case schematicVerified = "SCHEMATIC_VERIFIED"
    case blocked = "BLOCKED"
}

struct SchematicVerificationEvidence: Codable, Sendable, Equatable {
    var approvedDesignIntent: Bool
    var circuitIRValidationPassed: Bool
    var kicadProjectPath: String?
    var kicadSchematicPath: String?
    var ercReportPath: String?
    var hasSchematicVerificationReport: Bool
    var blockingERCViolations: [KiCadERCViolation]
    var repairLoopStatus: ERCRepairLoopStatus

    static let missingEvidence = SchematicVerificationEvidence(
        approvedDesignIntent: false,
        circuitIRValidationPassed: false,
        kicadProjectPath: nil,
        kicadSchematicPath: nil,
        ercReportPath: nil,
        hasSchematicVerificationReport: false,
        blockingERCViolations: [],
        repairLoopStatus: .blocked
    )

    static let complete = SchematicVerificationEvidence(
        approvedDesignIntent: true,
        circuitIRValidationPassed: true,
        kicadProjectPath: "/tmp/project.kicad_pro",
        kicadSchematicPath: "/tmp/project.kicad_sch",
        ercReportPath: "/tmp/erc.json",
        hasSchematicVerificationReport: true,
        blockingERCViolations: [],
        repairLoopStatus: .verified
    )
}

struct SchematicVerificationReport: Codable, Sendable, Equatable {
    var status: SchematicVerificationStatus
    var statusCode: String
    var missingEvidence: [SchematicVerificationEvidenceKey]
    var blockingERCViolations: [KiCadERCViolation]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct SchematicVerificationResult: Codable, Sendable, Equatable {
    var status: SchematicVerificationStatus
    var report: SchematicVerificationReport
    var missingEvidence: [SchematicVerificationEvidenceKey]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct SchematicVerificationGate: Sendable {
    func evaluate(_ evidence: SchematicVerificationEvidence) -> SchematicVerificationResult {
        var missing: [SchematicVerificationEvidenceKey] = []
        var diagnostics: [ElectronicsSchemaIssue] = []

        if !evidence.approvedDesignIntent {
            missing.append(.approvedDesignIntent)
        }
        if !evidence.circuitIRValidationPassed {
            missing.append(.circuitIRValidation)
        }
        if evidence.kicadProjectPath?.isEmpty ?? true {
            missing.append(.kicadProject)
        }
        if evidence.kicadSchematicPath?.isEmpty ?? true {
            missing.append(.kicadSchematic)
        }
        if evidence.ercReportPath?.isEmpty ?? true {
            missing.append(.ercReport)
        }
        if !evidence.hasSchematicVerificationReport {
            missing.append(.schematicVerificationReport)
        }

        if !evidence.blockingERCViolations.isEmpty {
            diagnostics.append(contentsOf: evidence.blockingERCViolations.map { violation in
                ElectronicsSchemaIssue(code: "BLOCKING_ERC_VIOLATION", message: violation.message)
            })
        }
        if evidence.repairLoopStatus != .verified {
            diagnostics.append(ElectronicsSchemaIssue(
                code: "SCHEMATIC_REPAIR_NOT_VERIFIED",
                message: "ERC repair loop has not reached a verified schematic state."
            ))
        }

        let status: SchematicVerificationStatus = missing.isEmpty && diagnostics.isEmpty
            ? .schematicVerified
            : .blocked
        let report = SchematicVerificationReport(
            status: status,
            statusCode: status.rawValue,
            missingEvidence: missing,
            blockingERCViolations: evidence.blockingERCViolations,
            diagnostics: diagnostics
        )
        return SchematicVerificationResult(
            status: status,
            report: report,
            missingEvidence: missing,
            diagnostics: diagnostics
        )
    }
}

private struct FlexibleERCReport: Decodable {
    var violations: [FlexibleERCViolation]

    enum CodingKeys: String, CodingKey {
        case violations
        case errors
        case sheets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topLevelViolations = try container.decodeIfPresent([FlexibleERCViolation].self, forKey: .violations) ?? []
        let errors = try container.decodeIfPresent([FlexibleERCViolation].self, forKey: .errors) ?? []
        let sheetViolations = try container
            .decodeIfPresent([FlexibleERCSheet].self, forKey: .sheets)?
            .flatMap(\.violations) ?? []
        self.violations = topLevelViolations + errors + sheetViolations
    }
}

private struct FlexibleERCSheet: Decodable {
    var violations: [FlexibleERCViolation]
}

private struct FlexibleERCViolation: Decodable {
    var violation: KiCadERCViolation

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case type
        case severity
        case message
        case description
        case refs
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let code = try container.decodeIfPresent(String.self, forKey: .code)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? "unknown"
        let severityText = (try container.decodeIfPresent(String.self, forKey: .severity) ?? "error").lowercased()
        let severity = KiCadERCSeverity(rawValue: severityText) ?? .error
        let message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? code
        let directRefs = (try? container.decodeIfPresent([String].self, forKey: .refs)) ?? nil
        let stringItems = (try? container.decodeIfPresent([String].self, forKey: .items)) ?? nil
        let objectItems = (try? container.decodeIfPresent([FlexibleERCItem].self, forKey: .items)) ?? nil
        let refs = directRefs ?? stringItems ?? (objectItems ?? []).map(\.reference)
        self.violation = KiCadERCViolation(
            id: id,
            code: code,
            severity: severity,
            message: message,
            refs: refs
        )
    }
}

private struct FlexibleERCItem: Decodable {
    var reference: String

    enum CodingKeys: String, CodingKey {
        case description
        case uuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .uuid)
            ?? ""
    }
}
