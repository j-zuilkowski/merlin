import Foundation

/// An individual override event appended to `.merlin/override-log.jsonl`.
struct OverrideEntry: Sendable, Codable {
    let timestamp: Date
    let category: String
    let file: String
    let line: Int
    let rationale: String
    let userDismissed: Bool
    let viaAnnotation: Bool
    let annotationText: String?
}

/// Persists override events to a JSONL file and runs weekly review.
actor OverrideAuditLog {

    private let logPath: String
    private let weeklyThreshold = 5

    init(logPath: String) {
        self.logPath = logPath
    }

    func record(_ entry: OverrideEntry) async throws {
        let data = try JSONEncoder().encode(entry)
        guard let line = String(data: data, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true, attributes: nil)

        if FileManager.default.fileExists(atPath: logPath) {
            guard let lineData = (line + "\n").data(using: .utf8) else { return }
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(lineData)
            handle.closeFile()
        } else {
            try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }

        TelemetryEmitter.shared.emit("discipline.override.recorded", data: [
            "category": entry.category,
            "file": entry.file,
            "line": entry.line,
            "rationale": entry.rationale
        ])
    }

    func entries(since date: Date) async -> [OverrideEntry] {
        loadAll().filter { $0.timestamp >= date }
    }

    func weeklyReview(queue: PendingAttentionQueue) async {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = loadAll().filter { $0.timestamp >= cutoff }

        var counts: [String: Int] = [:]
        for entry in recent {
            counts[entry.category, default: 0] += 1
        }

        for (category, count) in counts where count > weeklyThreshold {
            let now = Date()
            let finding = Finding(
                id: UUID(),
                category: .overrideAuditAccumulation,
                severity: .nudge,
                summary: "\(count) overrides in '\(category)' this week",
                detail: "You've used '\(category)' overrides \(count) times in the past 7 days. Is the trigger list too aggressive, or are you cutting corners?",
                suggestedAction: "Review override-log.jsonl or relax the trigger via adapter config",
                createdAt: now,
                lastSeenAt: now
            )
            await queue.add(finding)
            TelemetryEmitter.shared.emit("discipline.override-audit", data: [
                "category": category,
                "count": count,
                "threshold": weeklyThreshold
            ])
        }
    }

    private func loadAll() -> [OverrideEntry] {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(OverrideEntry.self, from: data)
            }
    }
}
