import Foundation

/// Persisted queue of discipline findings the user has not yet addressed.
/// Persists to `.merlin/pending.json`. Thread-safe via actor isolation.
actor PendingAttentionQueue {

    // MARK: - Storage

    private let storePath: String
    /// Keyed by `Finding.dedupKey` rather than `Finding.id`.
    private var findings: [String: Finding] = [:]

    // MARK: - Init

    init(storePath: String) {
        self.storePath = storePath
        if let loaded = Self.loadFromDisk(storePath) {
            self.findings = Dictionary(
                loaded.map { ($0.dedupKey, $0) },
                uniquingKeysWith: { _, newer in newer }
            )
        }
    }

    // MARK: - API

    func add(_ finding: Finding) async {
        if let existing = findings[finding.dedupKey] {
            findings[finding.dedupKey] = Finding(
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
            findings[finding.dedupKey] = finding
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
        guard let key = findings.first(where: { $0.value.id == id })?.key else {
            return
        }
        let removed = findings.removeValue(forKey: key)
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
        // No queue file yet = nothing persisted. Check existence explicitly so a
        // missing .merlin/pending.json never constructs an NSFileReadNoSuchFileError.
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Finding].self, from: data)
    }
}
