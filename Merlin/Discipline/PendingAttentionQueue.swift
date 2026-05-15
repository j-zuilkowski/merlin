import Foundation

/// Persisted queue of discipline findings the user has not yet addressed.
/// Persists to `.merlin/pending.json`. Thread-safe via actor isolation.
actor PendingAttentionQueue {

    // MARK: - Storage

    private let storePath: String
    private var findings: [UUID: Finding] = [:]

    // MARK: - Init

    init(storePath: String) {
        self.storePath = storePath
        if let loaded = Self.loadFromDisk(storePath) {
            self.findings = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        }
    }

    // MARK: - API

    func add(_ finding: Finding) async {
        if let existing = findings[finding.id] {
            findings[finding.id] = Finding(
                id: existing.id,
                category: existing.category,
                severity: existing.severity,
                summary: existing.summary,
                detail: existing.detail,
                suggestedAction: existing.suggestedAction,
                createdAt: existing.createdAt,
                lastSeenAt: finding.lastSeenAt
            )
        } else {
            findings[finding.id] = finding
        }

        persist()
        TelemetryEmitter.shared.emit("discipline.finding.added", data: [
            "category": finding.category.rawValue,
            "severity": finding.severity.rawValue
        ])
    }

    func all() async -> [Finding] {
        findings.values.sorted { $0.createdAt < $1.createdAt }
    }

    func top(n: Int) async -> [Finding] {
        let sorted = findings.values.sorted {
            if $0.severity != $1.severity {
                return $0.severity < $1.severity
            }
            return $0.lastSeenAt > $1.lastSeenAt
        }
        return Array(sorted.prefix(n))
    }

    func dismiss(id: UUID, rationale: String) async {
        let removed = findings.removeValue(forKey: id)
        persist()
        if let removed {
            TelemetryEmitter.shared.emit("discipline.finding.dismissed", data: [
                "category": removed.category.rawValue,
                "rationale": rationale
            ])
        }
    }

    // MARK: - Persistence

    private func persist() {
        let list = Array(findings.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        let url = URL(fileURLWithPath: storePath)
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func loadFromDisk(_ path: String) -> [Finding]? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Finding].self, from: data)
    }
}
