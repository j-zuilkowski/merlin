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

struct ElectronicsToolingState: Codable, Sendable, Equatable {
    var kiCadAvailable: Bool
    var localFreeRoutingAvailable: Bool
    var hostedFreeRoutingConfigured: Bool

    static let available = ElectronicsToolingState(
        kiCadAvailable: true,
        localFreeRoutingAvailable: true,
        hostedFreeRoutingConfigured: false
    )

    static let missingKiCad = ElectronicsToolingState(
        kiCadAvailable: false,
        localFreeRoutingAvailable: true,
        hostedFreeRoutingConfigured: false
    )

    static let missingLocalFreeRouting = ElectronicsToolingState(
        kiCadAvailable: true,
        localFreeRoutingAvailable: false,
        hostedFreeRoutingConfigured: false
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
