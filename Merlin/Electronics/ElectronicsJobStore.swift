import Combine
import Foundation

struct ElectronicsJobDiagnostic: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var questions: [String]
    var evidencePaths: [String]
    var requiredEvidenceCategories: [String]

    init(
        code: String,
        message: String,
        questions: [String] = [],
        evidencePaths: [String] = [],
        requiredEvidenceCategories: [String] = []
    ) {
        self.code = code
        self.message = message
        self.questions = questions
        self.evidencePaths = evidencePaths
        self.requiredEvidenceCategories = requiredEvidenceCategories
    }
}

struct ElectronicsJobApprovalRequest: Codable, Sendable, Equatable {
    var kind: ElectronicsApprovalKind
    var summary: String
}

struct ElectronicsJobProgressEntry: Codable, Sendable, Equatable {
    var message: String
}

struct ElectronicsEndToEndJobProgress: Codable, Sendable, Equatable {
    var jobID: String
    var result: ElectronicsEndToEndResult
    var message: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case result
        case message
    }
}

enum ElectronicsJobDisplayBucket: String, Codable, Sendable, Equatable {
    case running
    case blocked
    case fabReady
    case complete
}

struct ElectronicsJobDisplayState: Codable, Sendable, Equatable, Identifiable {
    var jobID: String
    var statusLabel: String
    var message: String
    var bucket: ElectronicsJobDisplayBucket
    var blockedQuestions: [String]
    var evidencePaths: [String]
    var requiredEvidenceCategories: [String]

    var id: String { jobID }

    init(
        jobID: String,
        statusLabel: String,
        message: String,
        bucket: ElectronicsJobDisplayBucket,
        blockedQuestions: [String] = [],
        evidencePaths: [String] = [],
        requiredEvidenceCategories: [String] = []
    ) {
        self.jobID = jobID
        self.statusLabel = statusLabel
        self.message = message
        self.bucket = bucket
        self.blockedQuestions = blockedQuestions
        self.evidencePaths = evidencePaths
        self.requiredEvidenceCategories = requiredEvidenceCategories
    }
}

struct ElectronicsJob: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var status: KiCadStatus
    var progress: [ElectronicsJobProgressEntry]
    var artifacts: [WorkspaceArtifactRef]
    var diagnostics: [ElectronicsJobDiagnostic]
    var approvalRequests: [ElectronicsJobApprovalRequest]
    var reports: [ElectronicsFinalReport]
    var endToEndResult: ElectronicsEndToEndResult?

    init(id: String, status: KiCadStatus = .inProgress) {
        self.id = id
        self.status = status
        self.progress = []
        self.artifacts = []
        self.diagnostics = []
        self.approvalRequests = []
        self.reports = []
        self.endToEndResult = nil
    }

    var isRunning: Bool {
        displayState.bucket == .running
    }

    var latestProgressMessage: String {
        progress.last?.message ?? status.rawValue
    }

    var blockedQuestions: [String] {
        diagnostics.flatMap(\.questions)
    }

    var diagnosticEvidencePaths: [String] {
        diagnostics.flatMap(\.evidencePaths)
    }

    var requiredEvidenceCategories: [String] {
        diagnostics.flatMap(\.requiredEvidenceCategories)
    }

    var workflowStatusLabel: String {
        displayState.statusLabel
    }

    var missingEvidenceLabels: [String] {
        endToEndResult?.missingEvidence ?? []
    }

    var displayState: ElectronicsJobDisplayState {
        if let endToEndResult {
            return ElectronicsJobDisplayState(
                jobID: id,
                statusLabel: endToEndResult.status.rawValue,
                message: latestProgressMessage,
                bucket: bucket(for: endToEndResult.status),
                blockedQuestions: blockedQuestions,
                evidencePaths: diagnosticEvidencePaths,
                requiredEvidenceCategories: requiredEvidenceCategories
            )
        }
        return ElectronicsJobDisplayState(
            jobID: id,
            statusLabel: status.rawValue,
            message: latestProgressMessage,
            bucket: bucket(for: status),
            blockedQuestions: blockedQuestions,
            evidencePaths: diagnosticEvidencePaths,
            requiredEvidenceCategories: requiredEvidenceCategories
        )
    }

    private func bucket(for status: ElectronicsEndToEndStatus) -> ElectronicsJobDisplayBucket {
        switch status {
        case .blocked:
            return .blocked
        case .complete:
            return .complete
        case .fabReady:
            return .fabReady
        case .schematicVerified, .pcbVerified:
            return .running
        }
    }

    private func bucket(for status: KiCadStatus) -> ElectronicsJobDisplayBucket {
        switch status {
        case .complete:
            return .complete
        case .inProgress:
            return .running
        default:
            return .blocked
        }
    }
}

@MainActor
final class ElectronicsJobStore: ObservableObject {
    @Published private(set) var jobs: [ElectronicsJob] = []
    private var subscriptionTask: Task<Void, Never>?

    var leaderboardJobs: [ElectronicsJob] {
        jobs.sorted { lhs, rhs in
            if sortRank(lhs.displayState.bucket) != sortRank(rhs.displayState.bucket) {
                return sortRank(lhs.displayState.bucket) < sortRank(rhs.displayState.bucket)
            }
            return lhs.id < rhs.id
        }
    }

    var leaderboardRows: [ElectronicsJobDisplayState] {
        leaderboardJobs.map(\.displayState)
    }

    var runningJobs: [ElectronicsJob] {
        leaderboardJobs.filter { $0.displayState.bucket == .running }
    }

    var runningRows: [ElectronicsJobDisplayState] {
        runningJobs.map(\.displayState)
    }

    var blockedJobs: [ElectronicsJob] {
        leaderboardJobs.filter { $0.displayState.bucket == .blocked }
    }

    var blockedRows: [ElectronicsJobDisplayState] {
        blockedJobs.map(\.displayState)
    }

    var fabReadyJobs: [ElectronicsJob] {
        leaderboardJobs.filter { $0.displayState.bucket == .fabReady }
    }

    var fabReadyRows: [ElectronicsJobDisplayState] {
        fabReadyJobs.map(\.displayState)
    }

    var completedJobs: [ElectronicsJob] {
        leaderboardJobs.filter { $0.displayState.bucket == .complete }
    }

    var completedRows: [ElectronicsJobDisplayState] {
        completedJobs.map(\.displayState)
    }

    deinit {
        subscriptionTask?.cancel()
    }

    func start(bus: WorkspaceMessageBus) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            let stream = await bus.subscribe(WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    func loadRecent(from bus: WorkspaceMessageBus) async {
        let events = await bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        for event in events {
            apply(event)
        }
    }

    func apply(_ event: WorkspaceMessageEvent) {
        switch event.kind {
        case .progress, .healthChanged:
            applyProgress(event)
        case .artifactProduced:
            applyArtifact(event)
        case .diagnostic:
            applyDiagnostic(event)
        case .approvalRequired:
            applyApproval(event)
        case .settingsChanged, .settingsValidation:
            break
        }
        jobs.sort { $0.id < $1.id }
    }

    private func applyProgress(_ event: WorkspaceMessageEvent) {
        if let eventPayload = event.payload,
           let harnessProgress = try? eventPayload.decodeJSON(ElectronicsEndToEndJobProgress.self) {
            var job = jobForUpdate(id: harnessProgress.jobID)
            job.endToEndResult = harnessProgress.result
            job.status = status(for: harnessProgress.result.status)
            job.progress.append(ElectronicsJobProgressEntry(
                message: harnessProgress.message ?? harnessProgress.result.status.rawValue
            ))
            upsert(job)
            return
        }

        guard let object = event.payload?.jsonObject(),
              let jobID = object["job_id"] as? String,
              let statusRaw = object["status"] as? String,
              let status = KiCadStatus(rawValue: statusRaw) else { return }
        let message = object["message"] as? String ?? status.rawValue
        var job = jobForUpdate(id: jobID)
        job.status = status
        job.progress.append(ElectronicsJobProgressEntry(message: message))
        upsert(job)
    }

    private func applyArtifact(_ event: WorkspaceMessageEvent) {
        guard let eventPayload = event.payload,
              let artifact = try? eventPayload.decodeJSON(WorkspaceArtifactRef.self),
              let jobID = artifact.metadata["job_id"] else {
            applyReport(event)
            return
        }
        var job = jobForUpdate(id: jobID)
        job.artifacts.removeAll { $0.id == artifact.id }
        job.artifacts.append(artifact)
        upsert(job)
    }

    private func applyReport(_ event: WorkspaceMessageEvent) {
        guard let eventPayload = event.payload,
              let report = try? eventPayload.decodeJSON(ElectronicsFinalReport.self) else { return }
        var job = jobForUpdate(id: report.jobID)
        job.status = report.status
        job.reports.removeAll { $0.jobID == report.jobID }
        job.reports.append(report)
        upsert(job)
    }

    private func applyDiagnostic(_ event: WorkspaceMessageEvent) {
        guard let object = event.payload?.jsonObject(),
              let jobID = object["job_id"] as? String,
              let code = object["code"] as? String else { return }
        let message = object["message"] as? String ?? code
        var job = jobForUpdate(id: jobID)
        if let statusRaw = object["status"] as? String,
           let status = KiCadStatus(rawValue: statusRaw) {
            job.status = status
        } else {
            job.status = .blocked
        }
        job.diagnostics.append(ElectronicsJobDiagnostic(
            code: code,
            message: message,
            questions: diagnosticQuestions(from: object),
            evidencePaths: diagnosticEvidencePaths(from: object),
            requiredEvidenceCategories: diagnosticRequiredEvidenceCategories(from: object)
        ))
        upsert(job)
    }

    private func applyApproval(_ event: WorkspaceMessageEvent) {
        guard let object = event.payload?.jsonObject(),
              let jobID = object["job_id"] as? String,
              let kindRaw = object["kind"] as? String,
              let kind = ElectronicsApprovalKind(rawValue: kindRaw) else { return }
        let summary = object["summary"] as? String ?? kind.rawValue
        var job = jobForUpdate(id: jobID)
        job.approvalRequests.append(ElectronicsJobApprovalRequest(kind: kind, summary: summary))
        upsert(job)
    }

    private func jobForUpdate(id: String) -> ElectronicsJob {
        jobs.first { $0.id == id } ?? ElectronicsJob(id: id)
    }

    private func upsert(_ job: ElectronicsJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
    }

    private func status(for status: ElectronicsEndToEndStatus) -> KiCadStatus {
        switch status {
        case .blocked:
            return .blocked
        case .complete:
            return .complete
        case .schematicVerified, .pcbVerified, .fabReady:
            return .inProgress
        }
    }

    private func sortRank(_ bucket: ElectronicsJobDisplayBucket) -> Int {
        switch bucket {
        case .running:
            return 0
        case .blocked:
            return 1
        case .fabReady:
            return 2
        case .complete:
            return 3
        }
    }

    private func diagnosticQuestions(from object: [String: Any]) -> [String] {
        guard let questions = object["questions"] as? [[String: Any]] else { return [] }
        return questions.compactMap { $0["prompt"] as? String }
    }

    private func diagnosticEvidencePaths(from object: [String: Any]) -> [String] {
        var paths = stringArray(in: object, keys: ["evidence_paths", "evidencePaths"])
        if let artifacts = object["artifacts"] as? [[String: Any]] {
            paths.append(contentsOf: artifacts.compactMap { $0["path"] as? String })
        }
        if let handoff = object["handoff"] as? [String: Any] {
            for key in [
                "original_component_matrix_path",
                "component_matrix_path",
                "design_intent_path",
                "circuit_ir_path",
            ] {
                paths.append(contentsOf: stringArray(in: handoff, keys: [key]))
            }
        }
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private func diagnosticRequiredEvidenceCategories(from object: [String: Any]) -> [String] {
        let explicit = stringArray(in: object, keys: ["required_evidence_categories", "requiredEvidenceCategories"])
        guard explicit.isEmpty else { return explicit }
        let questionText = diagnosticQuestions(from: object).joined(separator: " ").lowercased()
        let categories = [
            ("manufacturer", "manufacturer"),
            ("mpn", "mpn"),
            ("package", "package"),
            ("ratings", "ratings"),
            ("datasheet", "datasheet"),
            ("footprint_pin_compatibility", "footprint"),
            ("footprint_pin_compatibility", "pin compatibility"),
        ]
        var values: [String] = []
        for (category, needle) in categories where questionText.contains(needle) {
            if !values.contains(category) {
                values.append(category)
            }
        }
        return values
    }

    private func stringArray(in object: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = object[key] as? [String] {
                return value
            }
            if let value = object[key] as? String {
                return [value]
            }
        }
        return []
    }
}

private extension WorkspaceMessagePayload {
    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
