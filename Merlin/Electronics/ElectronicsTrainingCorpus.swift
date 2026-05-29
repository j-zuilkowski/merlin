import Foundation

enum ElectronicsTrainingTraceKind: String, Codable, Sendable, Equatable {
    case designIntentDraft = "design_intent_draft"
    case circuitIRValidation = "circuit_ir_validation"
    case diagnostic = "diagnostic"
    case repairOutcome = "repair_outcome"
}

enum ElectronicsTrainingOutcome: String, Codable, Sendable, Equatable {
    case accepted
    case rejected
}

enum ElectronicsDiagnosticKind: String, Codable, Sendable, Equatable {
    case erc
    case drc
    case spice
    case bom
}

enum ElectronicsVerifierStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case blocked
}

struct ElectronicsTrainingTrace: Codable, Sendable, Equatable {
    var id: String
    var designId: String
    var kind: ElectronicsTrainingTraceKind
    var requirementsText: String?
    var payloadJSON: String?
    var outcome: ElectronicsTrainingOutcome?
    var diagnosticKind: ElectronicsDiagnosticKind?
    var diagnosticCode: String?
    var patchJSON: String?
    var verifierStatus: ElectronicsVerifierStatus?
    var issues: [ElectronicsSchemaIssue]
    var createdAtISO8601: String
}

enum ElectronicsTrainingPairKind: String, Codable, Sendable, Equatable {
    case requirementsToIntent = "requirements_to_intent"
    case intentToCircuitIR = "intent_to_circuit_ir"
    case diagnosticsToPatch = "diagnostics_to_patch"
    case patchToVerifierResult = "patch_to_verifier_result"
}

struct ElectronicsTrainingPair: Codable, Sendable, Equatable {
    var kind: ElectronicsTrainingPairKind
    var input: String
    var output: String
    var accepted: Bool
}

struct ElectronicsTrainingCorpusStore: Sendable {
    var rootURL: URL

    private var tracesURL: URL {
        rootURL.appendingPathComponent("traces.jsonl")
    }

    func recordDesignIntentDraft(
        designId: String,
        requirementsText: String,
        draftJSON: String,
        decision: ElectronicsTrainingOutcome,
        issues: [ElectronicsSchemaIssue]
    ) throws {
        try append(ElectronicsTrainingTrace(
            id: UUID().uuidString,
            designId: designId,
            kind: .designIntentDraft,
            requirementsText: requirementsText,
            payloadJSON: draftJSON,
            outcome: decision,
            diagnosticKind: nil,
            diagnosticCode: nil,
            patchJSON: nil,
            verifierStatus: nil,
            issues: issues,
            createdAtISO8601: Self.timestamp()
        ))
    }

    func recordCircuitIRValidation(
        designId: String,
        circuitIRJSON: String,
        issues: [ElectronicsSchemaIssue]
    ) throws {
        try append(ElectronicsTrainingTrace(
            id: UUID().uuidString,
            designId: designId,
            kind: .circuitIRValidation,
            requirementsText: nil,
            payloadJSON: circuitIRJSON,
            outcome: issues.isEmpty ? .accepted : .rejected,
            diagnosticKind: nil,
            diagnosticCode: nil,
            patchJSON: nil,
            verifierStatus: nil,
            issues: issues,
            createdAtISO8601: Self.timestamp()
        ))
    }

    func recordDiagnostic(
        designId: String,
        diagnosticKind: ElectronicsDiagnosticKind,
        issues: [ElectronicsSchemaIssue]
    ) throws {
        try append(ElectronicsTrainingTrace(
            id: UUID().uuidString,
            designId: designId,
            kind: .diagnostic,
            requirementsText: nil,
            payloadJSON: nil,
            outcome: issues.isEmpty ? .accepted : .rejected,
            diagnosticKind: diagnosticKind,
            diagnosticCode: issues.first?.code,
            patchJSON: nil,
            verifierStatus: nil,
            issues: issues,
            createdAtISO8601: Self.timestamp()
        ))
    }

    func recordRepairOutcome(
        designId: String,
        diagnosticCode: String,
        patchJSON: String,
        verifierStatus: ElectronicsVerifierStatus
    ) throws {
        try append(ElectronicsTrainingTrace(
            id: UUID().uuidString,
            designId: designId,
            kind: .repairOutcome,
            requirementsText: nil,
            payloadJSON: nil,
            outcome: verifierStatus == .passed ? .accepted : .rejected,
            diagnosticKind: nil,
            diagnosticCode: diagnosticCode,
            patchJSON: patchJSON,
            verifierStatus: verifierStatus,
            issues: [],
            createdAtISO8601: Self.timestamp()
        ))
    }

    func loadTraces() throws -> [ElectronicsTrainingTrace] {
        guard FileManager.default.fileExists(atPath: tracesURL.path) else { return [] }
        let text = try String(contentsOf: tracesURL, encoding: .utf8)
        return try text
            .split(whereSeparator: \.isNewline)
            .map { line in
                try JSONDecoder().decode(ElectronicsTrainingTrace.self, from: Data(line.utf8))
            }
    }

    func trainingPairs() throws -> [ElectronicsTrainingPair] {
        try loadTraces().compactMap { trace in
            switch trace.kind {
            case .designIntentDraft:
                return ElectronicsTrainingPair(
                    kind: .requirementsToIntent,
                    input: trace.requirementsText ?? "",
                    output: trace.payloadJSON ?? "",
                    accepted: trace.outcome == .accepted
                )
            case .circuitIRValidation:
                return ElectronicsTrainingPair(
                    kind: .intentToCircuitIR,
                    input: trace.designId,
                    output: trace.payloadJSON ?? "",
                    accepted: trace.outcome == .accepted
                )
            case .diagnostic:
                return ElectronicsTrainingPair(
                    kind: .diagnosticsToPatch,
                    input: trace.issues.map(\.code).joined(separator: ","),
                    output: "",
                    accepted: false
                )
            case .repairOutcome:
                return ElectronicsTrainingPair(
                    kind: .patchToVerifierResult,
                    input: trace.patchJSON ?? "",
                    output: trace.verifierStatus?.rawValue ?? "",
                    accepted: trace.verifierStatus == .passed
                )
            }
        }
    }

    private func append(_ trace: ElectronicsTrainingTrace) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(trace)
        if FileManager.default.fileExists(atPath: tracesURL.path) {
            let handle = try FileHandle(forWritingTo: tracesURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: tracesURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

struct ElectronicsEvaluationManifest: Codable, Sendable, Equatable {
    var scenarios: [ElectronicsEvaluationScenario]

    static func load(from url: URL) throws -> ElectronicsEvaluationManifest {
        try JSONDecoder().decode(ElectronicsEvaluationManifest.self, from: Data(contentsOf: url))
    }
}

struct ElectronicsEvaluationScenario: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var fixturePath: String
    var requiredGates: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fixturePath = "fixture_path"
        case requiredGates = "required_gates"
    }
}
