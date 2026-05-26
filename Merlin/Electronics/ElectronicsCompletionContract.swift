import Foundation

enum ElectronicsWorkflowRoute: String, Codable, Sendable, Equatable, CaseIterable {
    case requirementsToPCB = "workflow.requirements_to_pcb"
    case schematicToPCB = "workflow.schematic_to_pcb"
}

enum ElectronicsArtifactKind: String, Codable, Sendable, Equatable, CaseIterable {
    case kicadProject = "kicad_project"
    case schematic = "kicad_schematic"
    case board = "kicad_board"
    case routingInterchange = "routing_interchange"
    case routingResult = "routing_result"
    case fabricationPackage = "fabrication_package"
    case bom = "bom"
    case pickAndPlace = "pick_and_place"
    case assemblyDrawing = "assembly_drawing"
    case stepModel = "step_model"
    case verificationReport = "verification_report"
    case approvalRecord = "approval_record"
}

enum ElectronicsVerificationGate: String, Codable, Sendable, Equatable, CaseIterable {
    case connectivity = "connectivity"
    case erc = "erc"
    case drc = "drc"
    case parity = "parity"
    case fabrication = "fabrication"
    case simulation = "simulation"
    case visualQA = "visual_qa"
    case highStakesSignoff = "high_stakes_signoff"
}

enum ElectronicsRoutingBackend: String, Codable, Sendable, Equatable {
    case localFreeRouting = "local_freerouting"
    case hostedFreeRouting = "hosted_freerouting"
}

enum HostedRoutingPolicy: String, Codable, Sendable, Equatable {
    case optionalConfigured = "optional_configured"
}

enum ElectronicsBlockedReason: String, Codable, Sendable, Equatable {
    case missingKiCad = "BLOCKED_KICAD_MISSING"
    case missingFreeRouting = "BLOCKED_FREEROUTING_MISSING"
    case unsupportedVersion = "BLOCKED_VERSION"
    case missingProjectFile = "BLOCKED_PROJECT_FILE"
    case invalidInputQuality = "BLOCKED_INPUT_QUALITY"
    case unresolvedFootprints = "BLOCKED_FOOTPRINTS"
    case routeFailed = "BLOCKED_ROUTE_FAILED"
    case unroutedNets = "BLOCKED_UNROUTED_NETS"
    case failedGate = "BLOCKED_VERIFICATION_GATE"
    case missingArtifact = "BLOCKED_ARTIFACT"
}

enum ElectronicsGateStatus: String, Codable, Sendable, Equatable {
    case pass = "PASS"
    case fail = "FAIL"
    case notApplicable = "NOT_APPLICABLE"
}

struct ElectronicsCompletionArtifact: Codable, Sendable, Equatable {
    var kind: ElectronicsArtifactKind
    var path: String

    static let requiredFixtureArtifacts: [ElectronicsCompletionArtifact] = [
        ElectronicsCompletionArtifact(kind: .kicadProject, path: "project.kicad_pro"),
        ElectronicsCompletionArtifact(kind: .schematic, path: "project.kicad_sch"),
        ElectronicsCompletionArtifact(kind: .board, path: "project.kicad_pcb"),
        ElectronicsCompletionArtifact(kind: .routingInterchange, path: "project.dsn"),
        ElectronicsCompletionArtifact(kind: .routingResult, path: "project.ses"),
        ElectronicsCompletionArtifact(kind: .fabricationPackage, path: "fab.zip"),
        ElectronicsCompletionArtifact(kind: .bom, path: "bom.csv"),
        ElectronicsCompletionArtifact(kind: .pickAndPlace, path: "centroid.csv"),
        ElectronicsCompletionArtifact(kind: .verificationReport, path: "verification.json"),
        ElectronicsCompletionArtifact(kind: .approvalRecord, path: "approvals.json"),
    ]
}

struct ElectronicsGateResult: Codable, Sendable, Equatable {
    var gate: ElectronicsVerificationGate
    var status: ElectronicsGateStatus
    var details: String

    static let allPassingRequired: [ElectronicsVerificationGate: ElectronicsGateResult] = {
        var results: [ElectronicsVerificationGate: ElectronicsGateResult] = [:]
        for gate in ElectronicsCompletionContract.current.requiredGates {
            results[gate] = ElectronicsGateResult(gate: gate, status: .pass, details: "pass")
        }
        return results
    }()
}

struct ElectronicsApprovalRecord: Codable, Sendable, Equatable {
    var kind: ElectronicsApprovalKind
    var approvedBy: String
    var summary: String
}

struct ElectronicsCompletionEvidence: Codable, Sendable, Equatable {
    var artifacts: [ElectronicsCompletionArtifact]
    var gates: [ElectronicsVerificationGate: ElectronicsGateResult]
    var approvals: [ElectronicsApprovalRecord]
    var highStakes: Bool
}

struct ElectronicsCompletionEvaluation: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var artifacts: [ElectronicsCompletionArtifact]
    var gates: [ElectronicsGateResult]
    var approvals: [ElectronicsApprovalRecord]
    var missingArtifactKinds: [ElectronicsArtifactKind]
    var failedGates: [ElectronicsGateResult]
    var blockedReasons: [ElectronicsBlockedReason]
}

struct ElectronicsCompletionEvaluator: Sendable {
    var contract: ElectronicsCompletionContract = .current

    func evaluate(_ evidence: ElectronicsCompletionEvidence) -> ElectronicsCompletionEvaluation {
        var missingArtifacts: [ElectronicsArtifactKind] = []
        let presentArtifacts = Set(evidence.artifacts.map(\.kind))
        for kind in contract.requiredArtifactKinds where !presentArtifacts.contains(kind) {
            missingArtifacts.append(kind)
        }

        var gateResults = contract.requiredGates.compactMap { evidence.gates[$0] }
        var failedGates = gateResults.filter { $0.status == .fail }
        let suppliedGateSet = Set(gateResults.map(\.gate))
        for requiredGate in contract.requiredGates where !suppliedGateSet.contains(requiredGate) {
            let missingGate = ElectronicsGateResult(
                gate: requiredGate,
                status: .fail,
                details: "Required gate result is missing."
            )
            gateResults.append(missingGate)
            failedGates.append(missingGate)
        }

        if evidence.highStakes && !evidence.approvals.contains(where: { $0.kind == .highStakesSignoff }) {
            let signoff = ElectronicsGateResult(
                gate: .highStakesSignoff,
                status: .fail,
                details: "High-stakes electronics release requires explicit user signoff."
            )
            failedGates.removeAll { $0.gate == .highStakesSignoff }
            failedGates.append(signoff)
            gateResults.removeAll { $0.gate == .highStakesSignoff }
            gateResults.append(signoff)
        }

        var blockedReasons: [ElectronicsBlockedReason] = []
        if !missingArtifacts.isEmpty {
            blockedReasons.append(.missingArtifact)
        }
        if !failedGates.isEmpty {
            blockedReasons.append(.failedGate)
        }

        return ElectronicsCompletionEvaluation(
            status: blockedReasons.isEmpty ? .complete : .blocked,
            artifacts: evidence.artifacts,
            gates: gateResults.sorted { $0.gate.rawValue < $1.gate.rawValue },
            approvals: evidence.approvals,
            missingArtifactKinds: missingArtifacts,
            failedGates: failedGates.sorted { $0.gate.rawValue < $1.gate.rawValue },
            blockedReasons: blockedReasons
        )
    }
}

struct ElectronicsFinalReport: Codable, Sendable, Equatable {
    var jobID: String
    var status: KiCadStatus
    var artifacts: [ElectronicsCompletionArtifact]
    var gates: [ElectronicsGateResult]
    var approvals: [ElectronicsApprovalRecord]
    var blockedReasons: [ElectronicsBlockedReason]

    enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case status
        case artifacts
        case gates
        case approvals
        case blockedReasons
    }

    init(jobID: String, evaluation: ElectronicsCompletionEvaluation) {
        self.jobID = jobID
        self.status = evaluation.status
        self.artifacts = evaluation.artifacts
        self.gates = evaluation.gates
        self.approvals = evaluation.approvals
        self.blockedReasons = evaluation.blockedReasons
    }
}

struct ElectronicsToolingState: Codable, Sendable, Equatable {
    var kiCadAvailable: Bool
    var localFreeRoutingAvailable: Bool
    var hostedFreeRoutingConfigured: Bool
    var unsupportedVersion: Bool = false

    static let available = ElectronicsToolingState(
        kiCadAvailable: true,
        localFreeRoutingAvailable: true,
        hostedFreeRoutingConfigured: false,
        unsupportedVersion: false
    )

    static let missingKiCad = ElectronicsToolingState(
        kiCadAvailable: false,
        localFreeRoutingAvailable: true,
        hostedFreeRoutingConfigured: false,
        unsupportedVersion: false
    )

    static let missingLocalFreeRouting = ElectronicsToolingState(
        kiCadAvailable: true,
        localFreeRoutingAvailable: false,
        hostedFreeRoutingConfigured: false,
        unsupportedVersion: false
    )

    static let unsupportedVersion = ElectronicsToolingState(
        kiCadAvailable: true,
        localFreeRoutingAvailable: true,
        hostedFreeRoutingConfigured: false,
        unsupportedVersion: true
    )
}

struct ElectronicsCompletionContract: Codable, Sendable, Equatable {
    var requiredWorkflows: [ElectronicsWorkflowRoute]
    var requiredArtifactKinds: [ElectronicsArtifactKind]
    var requiredGates: [ElectronicsVerificationGate]
    var requiredRoutingBackend: ElectronicsRoutingBackend
    var hostedRoutingPolicy: HostedRoutingPolicy

    static let current = ElectronicsCompletionContract(
        requiredWorkflows: [.requirementsToPCB, .schematicToPCB],
        requiredArtifactKinds: [
            .kicadProject,
            .schematic,
            .board,
            .routingInterchange,
            .routingResult,
            .fabricationPackage,
            .bom,
            .pickAndPlace,
            .verificationReport,
            .approvalRecord,
        ],
        requiredGates: [
            .connectivity,
            .erc,
            .drc,
            .parity,
            .fabrication,
            .simulation,
            .visualQA,
            .highStakesSignoff,
        ],
        requiredRoutingBackend: .localFreeRouting,
        hostedRoutingPolicy: .optionalConfigured
    )
}

struct ElectronicsWorkflowRequest: Codable, Sendable, Equatable {
    var jobID: String
    var evidence: ElectronicsCompletionEvidence?

    enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case evidence
    }
}

struct ElectronicsEvidenceStore: Sendable {
    var rootURL: URL

    func save(report: ElectronicsFinalReport) throws -> URL {
        let directory = rootURL
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics", isDirectory: true)
            .appendingPathComponent(report.jobID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("final-report.json")
        try WorkspaceJSON.encoder.encode(report).write(to: url, options: .atomic)
        return url
    }
}

struct ElectronicsGateRunner: Sendable {
    var evaluator: ElectronicsCompletionEvaluator = ElectronicsCompletionEvaluator()

    func finalReport(jobID: String, evidence: ElectronicsCompletionEvidence) -> ElectronicsFinalReport {
        ElectronicsFinalReport(jobID: jobID, evaluation: evaluator.evaluate(evidence))
    }
}
