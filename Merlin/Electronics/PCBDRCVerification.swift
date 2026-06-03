import Foundation

struct BoardOutline: Codable, Sendable, Equatable {
    var widthMm: Double
    var heightMm: Double
}

struct PCBFootprintAssignment: Codable, Sendable, Equatable {
    var componentRefdes: String
    var footprintName: String
    var pinPadMap: [String: String]
}

struct PCBBoardCandidate: Codable, Sendable, Equatable {
    var boardProfile: BoardProfile
    var outline: BoardOutline
    var footprintAssignments: [PCBFootprintAssignment]
    var netClassPlan: NetClassPlan
    var placementPlan: PlacementPlan
}

struct PCBBoardPlanner: Sendable {
    func buildCandidate(
        circuitIR: CircuitIR,
        boardProfile: BoardProfile,
        outline: BoardOutline,
        footprintResolutions: [KiCadLibraryPinResolution]
    ) -> PCBBoardCandidate {
        let assignments = footprintResolutions.compactMap { resolution -> PCBFootprintAssignment? in
            guard let footprint = resolution.footprintEvidence else { return nil }
            return PCBFootprintAssignment(
                componentRefdes: resolution.componentRefdes,
                footprintName: footprint.name,
                pinPadMap: resolution.pinPadMap
            )
        }

        var classes: [String: [String: Double]] = [:]
        for net in circuitIR.nets {
            classes[net.netClass] = [
                "min_trace_mm": boardProfile.minTraceMm,
                "clearance_mm": boardProfile.minClearanceMm,
            ]
        }
        for constraint in circuitIR.constraints where constraint.kind == "clearance" {
            let numeric = constraint.value.replacingOccurrences(of: "mm", with: "")
            if let value = Double(numeric) {
                classes[constraint.target, default: [:]]["clearance_mm"] = value
            }
        }

        let placementHints = Dictionary(
            uniqueKeysWithValues: circuitIR.constraints
                .filter { $0.kind == "placement" }
                .map { ($0.target, $0.value) }
        )

        return PCBBoardCandidate(
            boardProfile: boardProfile,
            outline: outline,
            footprintAssignments: assignments,
            netClassPlan: NetClassPlan(designId: circuitIR.designId, classes: classes),
            placementPlan: PlacementPlan(
                designId: circuitIR.designId,
                hints: placementHints,
                keepouts: circuitIR.constraints.filter { $0.kind == "keepout" }.map(\.value)
            )
        )
    }
}

struct CircuitIRKiCadBoardMaterialization: Sendable, Equatable {
    var boardURL: URL
}

enum CircuitIRKiCadBoardMaterializerError: Error, Equatable {
    case invalidBoardEvidence([ElectronicsSchemaIssue])
}

struct CircuitIRKiCadBoardMaterializer: Sendable {
    func materialize(
        circuitIR: CircuitIR,
        outputDirectory: URL
    ) throws -> CircuitIRKiCadBoardMaterialization {
        let validation = validate(circuitIR: circuitIR)
        guard validation.isValid else {
            throw CircuitIRKiCadBoardMaterializerError.invalidBoardEvidence(validation.issues)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let boardURL = outputDirectory.appendingPathComponent("\(circuitIR.boardId).kicad_pcb")
        try boardText(circuitIR: circuitIR).write(to: boardURL, atomically: true, encoding: .utf8)
        return CircuitIRKiCadBoardMaterialization(boardURL: boardURL)
    }

    func validate(circuitIR: CircuitIR) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        for component in circuitIR.components {
            if component.selectedFootprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                issues.append(issue("PCB_FOOTPRINT_REQUIRED", "\(component.refdes) has no selected footprint."))
            }
            if component.pins.isEmpty {
                issues.append(issue("PCB_PINS_REQUIRED", "\(component.refdes) has no pin evidence."))
            }
            for pin in component.pins where pin.footprintPad?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                issues.append(issue("PCB_PIN_PAD_REQUIRED", "\(component.refdes).\(pin.pinNumber) has no footprint pad evidence."))
            }
        }
        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private func boardText(circuitIR: CircuitIR) -> String {
        let outline = boardOutline(componentCount: circuitIR.components.count)
        let netIDs = netIDsByName(circuitIR: circuitIR)
        let pinNetNames = netNamesByEndpoint(circuitIR: circuitIR)
        let nets = netIDs
            .sorted { $0.value < $1.value }
            .map { #"  (net \#($0.value) "\#(escaped($0.key))")"# }
            .joined(separator: "\n")
        let footprints = circuitIR.components.enumerated().map { index, component in
            footprintNode(
                component: component,
                index: index,
                outline: outline,
                netIDs: netIDs,
                pinNetNames: pinNetNames
            )
        }
            .joined(separator: "\n")

        return """
        (kicad_pcb
          (version 20250114)
          (generator "merlin-electronics")
          (general (thickness 1.6))
          (paper "A4")
          (layers
            (0 "F.Cu" signal)
            (31 "B.Cu" signal)
            (32 "B.Adhes" user "B.Adhesive")
            (33 "F.Adhes" user "F.Adhesive")
            (34 "B.Paste" user)
            (35 "F.Paste" user)
            (36 "B.SilkS" user "B.Silkscreen")
            (37 "F.SilkS" user "F.Silkscreen")
            (38 "B.Mask" user)
            (39 "F.Mask" user)
            (40 "Dwgs.User" user "User.Drawings")
            (41 "Cmts.User" user "User.Comments")
            (42 "Eco1.User" user "User.Eco1")
            (43 "Eco2.User" user "User.Eco2")
            (44 "Edge.Cuts" user)
            (45 "Margin" user)
            (46 "B.CrtYd" user "B.Courtyard")
            (47 "F.CrtYd" user)
            (48 "B.Fab" user)
            (49 "F.Fab" user)
          )
          (setup
            (pad_to_mask_clearance 0)
            (allow_soldermask_bridges_in_footprints no)
            (pcbplotparams)
          )
          (net 0 "")
        \(nets)
          (gr_rect
            (start 0 0)
            (end \(number(outline.widthMm)) \(number(outline.heightMm)))
            (stroke (width 0.1) (type default))
            (fill no)
            (layer "Edge.Cuts")
            (uuid "\(stableUUID("outline", circuitIR.designId, circuitIR.boardId))")
          )
        \(footprints)
        )
        """
    }

    private func footprintNode(
        component: CircuitComponent,
        index: Int,
        outline: BoardOutline,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String {
        let at = placement(index: index, outline: outline)
        let footprint = escaped(component.selectedFootprint ?? "Merlin:Unresolved")
        let value = escaped(component.constraints["value"] ?? component.manufacturerPartNumber ?? component.role)
        let pads = component.pins.enumerated().map { padIndex, pin in
            padNode(
                component: component,
                pin: pin,
                padIndex: padIndex,
                netIDs: netIDs,
                pinNetNames: pinNetNames
            )
        }
            .joined(separator: "\n")

        return """
          (footprint "\(footprint)"
            (layer "F.Cu")
            (uuid "\(stableUUID("footprint", component.refdes))")
            (at \(number(at.x)) \(number(at.y)) 0)
            (property "Reference" "\(escaped(component.refdes))" (at 0 -2 0) (layer "F.SilkS") (uuid "\(stableUUID("property", component.refdes, "reference"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (property "Value" "\(value)" (at 0 2 0) (layer "F.Fab") (uuid "\(stableUUID("property", component.refdes, "value"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (property "Footprint" "\(footprint)" (at 0 3.5 0) (layer "F.Fab") hide (uuid "\(stableUUID("property", component.refdes, "footprint"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (fp_text reference "\(escaped(component.refdes))" (at 0 -2 0) (layer "F.SilkS")
              (effects (font (size 1 1) (thickness 0.15))))
            (fp_text value "\(value)" (at 0 2 0) (layer "F.Fab")
              (effects (font (size 1 1) (thickness 0.15))))
            (attr through_hole)
        \(pads)
          )
        """
    }

    private func padNode(
        component: CircuitComponent,
        pin: CircuitPin,
        padIndex: Int,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String {
        let pad = escaped(pin.footprintPad ?? pin.pinNumber)
        let netName = pinNetNames["\(component.refdes)|\(pin.pinNumber)"] ?? ""
        let netID = netIDs[netName] ?? 0
        let net = netID == 0 ? "" : #" (net \#(netID) "\#(escaped(netName))")"#
        let x = Double(padIndex) * 2.54
        return #"    (pad "\#(pad)" thru_hole circle (at \#(number(x)) 0) (size 1.6 1.6) (drill 0.8) (layers "*.Cu" "*.Mask")\#(net) (uuid "\#(stableUUID("pad", component.refdes, pad))"))"#
    }

    private func netIDsByName(circuitIR: CircuitIR) -> [String: Int] {
        var result: [String: Int] = [:]
        for net in circuitIR.nets where !net.endpoints.isEmpty && result[net.name] == nil {
            result[net.name] = result.count + 1
        }
        return result
    }

    private func netNamesByEndpoint(circuitIR: CircuitIR) -> [String: String] {
        var result: [String: String] = [:]
        for net in circuitIR.nets {
            for endpoint in net.endpoints {
                result["\(endpoint.componentRefdes)|\(endpoint.pinNumber)"] = net.name
            }
        }
        return result
    }

    private func boardOutline(componentCount: Int) -> BoardOutline {
        let columns = min(max(componentCount, 1), 6)
        let rows = Int(ceil(Double(max(componentCount, 1)) / Double(columns)))
        return BoardOutline(widthMm: max(120, Double(columns) * 26 + 20), heightMm: max(80, Double(rows) * 22 + 20))
    }

    private func placement(index: Int, outline: BoardOutline) -> KiCadSchematicDocument.Point {
        let columns = max(1, Int((outline.widthMm - 20) / 26))
        let column = index % columns
        let row = index / columns
        return KiCadSchematicDocument.Point(x: 12 + Double(column) * 26, y: 14 + Double(row) * 22)
    }

    private func issue(_ code: String, _ message: String) -> ElectronicsSchemaIssue {
        ElectronicsSchemaIssue(code: code, message: message)
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == floor(rounded) {
            return String(Int(rounded))
        }
        return String(format: "%.3f", rounded).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    private func stableUUID(_ parts: String...) -> String {
        let input = parts.joined(separator: "|")
        let hash = input.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct FootprintAssignmentVerifier: Sendable {
    func verify(
        circuitIR: CircuitIR,
        resolutions: [KiCadLibraryPinResolution]
    ) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        let byRef = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.componentRefdes, $0) })

        for component in circuitIR.components {
            guard let resolution = byRef[component.refdes],
                  resolution.isResolved,
                  resolution.footprintEvidence != nil else {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(component.refdes) has no resolved footprint proof."
                ))
                continue
            }
            for pin in component.pins where resolution.pinPadMap[pin.symbolPin] == nil {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(component.refdes).\(pin.pinNumber) has no pin-pad proof."
                ))
            }
            for issue in resolution.issues {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(issue.affectedRef): \(issue.message)"
                ))
            }
        }

        return ElectronicsSchemaValidationResult(issues: issues)
    }
}

enum KiCadDRCSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case info

    var isBlocking: Bool {
        self == .error
    }
}

struct KiCadDRCViolation: Codable, Sendable, Equatable {
    var id: String
    var code: String
    var severity: KiCadDRCSeverity
    var message: String
    var refs: [String]
}

struct KiCadDRCReport: Codable, Sendable, Equatable {
    var violations: [KiCadDRCViolation]

    var blockingViolations: [KiCadDRCViolation] {
        violations.filter { $0.severity.isBlocking }
    }
}

struct KiCadDRCParser: Sendable {
    func parse(jsonData: Data) throws -> KiCadDRCReport {
        let root = try JSONDecoder().decode(FlexibleDRCReport.self, from: jsonData)
        return KiCadDRCReport(violations: root.violations.map(\.violation))
    }
}

enum PCBDRCRepairClass: String, Codable, Sendable, Equatable {
    case placement
    case routing
    case netClass = "net_class"
    case clearance
}

struct PCBDRCRepairPatch: Codable, Sendable, Equatable {
    var violationId: String
    var repairClass: PCBDRCRepairClass
    var targetRefs: [String]
    var action: String
}

enum PCBDRCRepairLoopStatus: String, Codable, Sendable, Equatable {
    case verified
    case blocked
}

struct PCBDRCRepairLoopResult: Codable, Sendable, Equatable {
    var status: PCBDRCRepairLoopStatus
    var attempts: Int
    var appliedPatches: [PCBDRCRepairPatch]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct PCBDRCRepairLoop: Sendable {
    var maxAttempts: Int = 3

    func run(drcReports: [KiCadDRCReport]) -> PCBDRCRepairLoopResult {
        var attempts = 0
        var applied: [PCBDRCRepairPatch] = []
        let reports = drcReports.isEmpty ? [KiCadDRCReport(violations: [])] : drcReports

        for report in reports {
            if report.blockingViolations.isEmpty {
                return PCBDRCRepairLoopResult(status: .verified, attempts: attempts, appliedPatches: applied, diagnostics: [])
            }
            if attempts >= maxAttempts {
                return blocked(
                    attempts: attempts,
                    applied: applied,
                    code: "DRC_REPAIR_ATTEMPTS_EXHAUSTED",
                    message: "DRC repair attempts exhausted before KiCad reported a clean PCB."
                )
            }

            var patches: [PCBDRCRepairPatch] = []
            for violation in report.blockingViolations {
                switch classify(violation) {
                case .repair(let repairClass):
                    patches.append(PCBDRCRepairPatch(
                        violationId: violation.id,
                        repairClass: repairClass,
                        targetRefs: violation.refs,
                        action: actionName(for: repairClass)
                    ))
                case .requiresApproval:
                    return blocked(
                        attempts: attempts,
                        applied: applied,
                        code: "DRC_REPAIR_REQUIRES_APPROVAL",
                        message: violation.message
                    )
                case .unsupported:
                    return blocked(
                        attempts: attempts,
                        applied: applied,
                        code: "UNSUPPORTED_DRC_VIOLATION",
                        message: violation.code
                    )
                }
            }

            attempts += 1
            applied.append(contentsOf: patches)
        }

        return blocked(
            attempts: attempts,
            applied: applied,
            code: "DRC_REPAIR_ATTEMPTS_EXHAUSTED",
            message: "DRC repair loop ended without a clean DRC report."
        )
    }

    private enum Classification {
        case repair(PCBDRCRepairClass)
        case requiresApproval
        case unsupported
    }

    private func classify(_ violation: KiCadDRCViolation) -> Classification {
        switch violation.code {
        case "courtyard_collision", "placement_overlap", "component_collision":
            return .repair(.placement)
        case "unrouted_net", "routing_incomplete":
            return .repair(.routing)
        case "net_class", "track_width":
            return .repair(.netClass)
        case "clearance", "copper_clearance":
            return .repair(.clearance)
        case "layer_count_change_required", "fabricator_profile_change_required":
            return .requiresApproval
        default:
            return .unsupported
        }
    }

    private func actionName(for repairClass: PCBDRCRepairClass) -> String {
        switch repairClass {
        case .placement:
            return "adjust_placement"
        case .routing:
            return "reroute_or_report_unrouted"
        case .netClass:
            return "adjust_net_class"
        case .clearance:
            return "adjust_clearance_rule"
        }
    }

    private func blocked(
        attempts: Int,
        applied: [PCBDRCRepairPatch],
        code: String,
        message: String
    ) -> PCBDRCRepairLoopResult {
        PCBDRCRepairLoopResult(
            status: .blocked,
            attempts: attempts,
            appliedPatches: applied,
            diagnostics: [ElectronicsSchemaIssue(code: code, message: message)]
        )
    }
}

enum PCBVerificationEvidenceKey: String, Codable, Sendable, Equatable {
    case schematicVerified = "schematic_verified"
    case footprintAssignment = "footprint_assignment"
    case boardProfile = "board_profile"
    case boardOutline = "board_outline"
    case stackup = "stackup"
    case netClasses = "net_classes"
    case placement = "placement"
    case routing = "routing"
    case drcReport = "drc_report"
    case pcbVerificationReport = "pcb_verification_report"
}

enum PCBVerificationStatus: String, Codable, Sendable, Equatable {
    case pcbVerified = "PCB_VERIFIED"
    case blocked = "BLOCKED"
}

struct PCBVerificationEvidence: Codable, Sendable, Equatable {
    var schematicVerified: Bool
    var footprintAssignmentPassed: Bool
    var hasBoardProfile: Bool
    var hasBoardOutline: Bool
    var hasStackup: Bool
    var hasNetClasses: Bool
    var hasPlacement: Bool
    var routingPassedOrExplicitlyDiagnosed: Bool
    var drcReportPath: String?
    var hasPCBVerificationReport: Bool
    var blockingDRCViolations: [KiCadDRCViolation]
    var repairLoopStatus: PCBDRCRepairLoopStatus

    enum CodingKeys: String, CodingKey {
        case schematicVerified
        case footprintAssignmentPassed
        case hasBoardProfile
        case hasBoardOutline
        case hasStackup
        case hasNetClasses
        case hasPlacement
        case routingPassedOrExplicitlyDiagnosed
        case drcReportPath
        case hasPCBVerificationReport
        case blockingDRCViolations
        case repairLoopStatus
    }

    init(
        schematicVerified: Bool,
        footprintAssignmentPassed: Bool,
        hasBoardProfile: Bool,
        hasBoardOutline: Bool,
        hasStackup: Bool,
        hasNetClasses: Bool,
        hasPlacement: Bool,
        routingPassedOrExplicitlyDiagnosed: Bool,
        drcReportPath: String?,
        hasPCBVerificationReport: Bool,
        blockingDRCViolations: [KiCadDRCViolation],
        repairLoopStatus: PCBDRCRepairLoopStatus
    ) {
        self.schematicVerified = schematicVerified
        self.footprintAssignmentPassed = footprintAssignmentPassed
        self.hasBoardProfile = hasBoardProfile
        self.hasBoardOutline = hasBoardOutline
        self.hasStackup = hasStackup
        self.hasNetClasses = hasNetClasses
        self.hasPlacement = hasPlacement
        self.routingPassedOrExplicitlyDiagnosed = routingPassedOrExplicitlyDiagnosed
        self.drcReportPath = drcReportPath
        self.hasPCBVerificationReport = hasPCBVerificationReport
        self.blockingDRCViolations = blockingDRCViolations
        self.repairLoopStatus = repairLoopStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PCBVerificationFlexibleCodingKey.self)
        schematicVerified = try container.decodeBool(keys: ["schematicVerified", "schematic_verified"])
        footprintAssignmentPassed = try container.decodeBool(keys: ["footprintAssignmentPassed", "footprint_assignment_passed"])
        hasBoardProfile = try container.decodeBool(keys: ["hasBoardProfile", "has_board_profile"])
        hasBoardOutline = try container.decodeBool(keys: ["hasBoardOutline", "has_board_outline"])
        hasStackup = try container.decodeBool(keys: ["hasStackup", "has_stackup"])
        hasNetClasses = try container.decodeBool(keys: ["hasNetClasses", "has_net_classes"])
        hasPlacement = try container.decodeBool(keys: ["hasPlacement", "has_placement"])
        routingPassedOrExplicitlyDiagnosed = try container.decodeBool(
            keys: ["routingPassedOrExplicitlyDiagnosed", "routing_passed_or_explicitly_diagnosed"]
        )
        drcReportPath = try container.decodeStringIfPresent(keys: ["drcReportPath", "drc_report_path"])
        hasPCBVerificationReport = try container.decodeBool(keys: [
            "hasPCBVerificationReport",
            "hasPcbVerificationReport",
            "has_pcb_verification_report",
        ])
        blockingDRCViolations = try container.decodeArrayIfPresent(
            [KiCadDRCViolation].self,
            keys: ["blockingDRCViolations", "blockingDrcViolations", "blocking_drc_violations"]
        ) ?? []
        repairLoopStatus = try container.decodeStatus(keys: ["repairLoopStatus", "repair_loop_status"])
    }

    static let missingEvidence = PCBVerificationEvidence(
        schematicVerified: false,
        footprintAssignmentPassed: false,
        hasBoardProfile: false,
        hasBoardOutline: false,
        hasStackup: false,
        hasNetClasses: false,
        hasPlacement: false,
        routingPassedOrExplicitlyDiagnosed: false,
        drcReportPath: nil,
        hasPCBVerificationReport: false,
        blockingDRCViolations: [],
        repairLoopStatus: .blocked
    )

    static let complete = PCBVerificationEvidence(
        schematicVerified: true,
        footprintAssignmentPassed: true,
        hasBoardProfile: true,
        hasBoardOutline: true,
        hasStackup: true,
        hasNetClasses: true,
        hasPlacement: true,
        routingPassedOrExplicitlyDiagnosed: true,
        drcReportPath: "/tmp/drc.json",
        hasPCBVerificationReport: true,
        blockingDRCViolations: [],
        repairLoopStatus: .verified
    )
}

private struct PCBVerificationFlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == PCBVerificationFlexibleCodingKey {
    func decodeBool(keys: [String]) throws -> Bool {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decode(Bool.self, forKey: codingKey)
        }
        throw DecodingError.keyNotFound(
            PCBVerificationFlexibleCodingKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing PCB verification evidence key.")
        )
    }

    func decodeStringIfPresent(keys: [String]) throws -> String? {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decodeIfPresent(String.self, forKey: codingKey)
        }
        return nil
    }

    func decodeArrayIfPresent<T: Decodable>(_ type: [T].Type, keys: [String]) throws -> [T]? {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decodeIfPresent(type, forKey: codingKey)
        }
        return nil
    }

    func decodeStatus(keys: [String]) throws -> PCBDRCRepairLoopStatus {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decode(PCBDRCRepairLoopStatus.self, forKey: codingKey)
        }
        throw DecodingError.keyNotFound(
            PCBVerificationFlexibleCodingKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing PCB DRC repair status key.")
        )
    }
}

struct PCBVerificationReport: Codable, Sendable, Equatable {
    var status: PCBVerificationStatus
    var statusCode: String
    var missingEvidence: [PCBVerificationEvidenceKey]
    var diagnostics: [ElectronicsSchemaIssue]
    var fabricationComplete: Bool
}

struct PCBVerificationResult: Codable, Sendable, Equatable {
    var status: PCBVerificationStatus
    var report: PCBVerificationReport
    var missingEvidence: [PCBVerificationEvidenceKey]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct PCBVerificationGate: Sendable {
    func evaluate(_ evidence: PCBVerificationEvidence) -> PCBVerificationResult {
        var missing: [PCBVerificationEvidenceKey] = []
        var diagnostics: [ElectronicsSchemaIssue] = []

        if !evidence.schematicVerified { missing.append(.schematicVerified) }
        if !evidence.footprintAssignmentPassed { missing.append(.footprintAssignment) }
        if !evidence.hasBoardProfile { missing.append(.boardProfile) }
        if !evidence.hasBoardOutline { missing.append(.boardOutline) }
        if !evidence.hasStackup { missing.append(.stackup) }
        if !evidence.hasNetClasses { missing.append(.netClasses) }
        if !evidence.hasPlacement { missing.append(.placement) }
        if !evidence.routingPassedOrExplicitlyDiagnosed { missing.append(.routing) }
        if evidence.drcReportPath?.isEmpty ?? true { missing.append(.drcReport) }
        if !evidence.hasPCBVerificationReport { missing.append(.pcbVerificationReport) }

        diagnostics.append(contentsOf: evidence.blockingDRCViolations.map {
            ElectronicsSchemaIssue(code: "BLOCKING_DRC_VIOLATION", message: $0.message)
        })
        if evidence.repairLoopStatus != .verified {
            diagnostics.append(ElectronicsSchemaIssue(
                code: "PCB_DRC_NOT_VERIFIED",
                message: "DRC repair loop has not reached a verified PCB state."
            ))
        }

        let status: PCBVerificationStatus = missing.isEmpty && diagnostics.isEmpty ? .pcbVerified : .blocked
        let report = PCBVerificationReport(
            status: status,
            statusCode: status.rawValue,
            missingEvidence: missing,
            diagnostics: diagnostics,
            fabricationComplete: false
        )

        return PCBVerificationResult(status: status, report: report, missingEvidence: missing, diagnostics: diagnostics)
    }
}

private struct FlexibleDRCReport: Decodable {
    var violations: [FlexibleDRCViolation]

    enum CodingKeys: String, CodingKey {
        case violations
        case errors
        case sheets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topLevel = try container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .violations)
            ?? container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .errors)
            ?? []
        let sheetLevel = try container.decodeIfPresent([FlexibleDRCSheet].self, forKey: .sheets)?
            .flatMap(\.violations) ?? []
        violations = topLevel + sheetLevel
    }
}

private struct FlexibleDRCSheet: Decodable {
    var violations: [FlexibleDRCViolation]

    enum CodingKeys: String, CodingKey {
        case violations
        case errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        violations = try container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .violations)
            ?? container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .errors)
            ?? []
    }
}

private struct FlexibleDRCViolation: Decodable {
    var violation: KiCadDRCViolation

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
        let severity = KiCadDRCSeverity(rawValue: severityText) ?? .error
        let message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? code
        let refs = try container.decodeIfPresent([String].self, forKey: .refs)
            ?? FlexibleDRCItemRefs.decode(from: decoder, key: .items)
            ?? []
        violation = KiCadDRCViolation(id: id, code: code, severity: severity, message: message, refs: refs)
    }
}

private enum FlexibleDRCItemRefs {
    static func decode(from decoder: Decoder, key: FlexibleDRCViolation.CodingKeys) -> [String]? {
        guard let container = try? decoder.container(keyedBy: FlexibleDRCViolation.CodingKeys.self),
              container.contains(key) else {
            return nil
        }
        if let strings = try? container.decode([String].self, forKey: key) {
            return strings
        }
        if let objects = try? container.decode([FlexibleDRCItem].self, forKey: key) {
            return objects.map(\.reference).filter { !$0.isEmpty }
        }
        return nil
    }
}

private struct FlexibleDRCItem: Decodable {
    var reference: String

    enum CodingKeys: String, CodingKey {
        case ref
        case reference
        case description
        case uuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decodeIfPresent(String.self, forKey: .ref)
            ?? container.decodeIfPresent(String.self, forKey: .reference)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .uuid)
            ?? ""
    }
}
