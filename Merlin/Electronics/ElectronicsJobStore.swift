import Combine
import Foundation

struct ElectronicsJobDiagnostic: Codable, Sendable, Equatable {
    var code: String
    var message: String
}

struct ElectronicsJobApprovalRequest: Codable, Sendable, Equatable {
    var kind: ElectronicsApprovalKind
    var summary: String
}

struct ElectronicsJobProgressEntry: Codable, Sendable, Equatable {
    var message: String
}

struct ElectronicsJob: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var status: KiCadStatus
    var progress: [ElectronicsJobProgressEntry]
    var artifacts: [WorkspaceArtifactRef]
    var diagnostics: [ElectronicsJobDiagnostic]
    var approvalRequests: [ElectronicsJobApprovalRequest]
    var reports: [ElectronicsFinalReport]

    init(id: String, status: KiCadStatus = .inProgress) {
        self.id = id
        self.status = status
        self.progress = []
        self.artifacts = []
        self.diagnostics = []
        self.approvalRequests = []
        self.reports = []
    }

    var isRunning: Bool {
        status == .inProgress
    }

    var latestProgressMessage: String {
        progress.last?.message ?? status.rawValue
    }
}

@MainActor
final class ElectronicsJobStore: ObservableObject {
    @Published private(set) var jobs: [ElectronicsJob] = []
    private var subscriptionTask: Task<Void, Never>?

    var leaderboardJobs: [ElectronicsJob] {
        jobs.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.id < rhs.id
        }
    }

    var runningJobs: [ElectronicsJob] {
        leaderboardJobs.filter(\.isRunning)
    }

    var completedJobs: [ElectronicsJob] {
        leaderboardJobs.filter { !$0.isRunning }
    }

    deinit {
        subscriptionTask?.cancel()
    }

    func start(bus: WorkspaceMessageBus) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            let stream = await bus.subscribe(WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
            for await event in stream {
                await self?.apply(event)
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
        job.diagnostics.append(ElectronicsJobDiagnostic(code: code, message: message))
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
}

private extension WorkspaceMessagePayload {
    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
