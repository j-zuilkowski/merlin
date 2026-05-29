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
        case severity
        case message
        case refs
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
        let severityText = (try container.decodeIfPresent(String.self, forKey: .severity) ?? "error").lowercased()
        let severity = KiCadDRCSeverity(rawValue: severityText) ?? .error
        let message = try container.decodeIfPresent(String.self, forKey: .message) ?? code
        let refs = try container.decodeIfPresent([String].self, forKey: .refs)
            ?? container.decodeIfPresent([String].self, forKey: .items)
            ?? []
        violation = KiCadDRCViolation(id: id, code: code, severity: severity, message: message, refs: refs)
    }
}
