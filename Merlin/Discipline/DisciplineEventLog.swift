import Foundation

/// JSONL store for structured `merlin-discipline` hook events.
actor DisciplineEventLog {

    private let logPath: String

    init(logPath: String) {
        self.logPath = logPath
    }

    func record(_ event: DisciplineEvent) async throws {
        let data = try JSONEncoder().encode(event)
        guard let line = String(data: data, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true, attributes: nil)

        guard let lineData = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logPath) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(lineData)
            handle.closeFile()
        } else {
            try lineData.write(to: url, options: .atomic)
        }
    }

    func events(since date: Date) async -> [DisciplineEvent] {
        loadAll().filter { $0.timestamp >= date }
    }

    private func loadAll() -> [DisciplineEvent] {
        // No log file yet = no events. Check existence explicitly so a missing
        // .merlin/discipline-events.jsonl never constructs an NSFileReadNoSuchFileError.
        guard FileManager.default.fileExists(atPath: logPath),
              let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(DisciplineEvent.self, from: data)
            }
    }
}
