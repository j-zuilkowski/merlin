import Foundation

// MARK: - DPOPendingEntry

/// A DPO (Direct Preference Optimization) training pair awaiting user review.
/// `chosen` is empty until the user fills it in via the review queue.
struct DPOPendingEntry: Codable, Sendable, Identifiable {
    var id: String
    var prompt: String
    var chosen: String
    var rejected: String
    var modelID: String
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        prompt: String,
        chosen: String,
        rejected: String,
        modelID: String,
        timestamp: Date
    ) {
        self.id = id
        self.prompt = prompt
        self.chosen = chosen
        self.rejected = rejected
        self.modelID = modelID
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case chosen
        case rejected
        case modelID = "model_id"
        case timestamp
    }
}

// MARK: - DPOQueue

/// Queue of proposed DPO training pairs at `~/.merlin/lora/pending/` — one JSON file
/// per entry, awaiting user approval before entering the training corpus (mirrors the
/// `memories/pending/` pattern).
actor DPOQueue {

    private let pendingDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.pendingDirectory = home
            .appendingPathComponent(".merlin")
            .appendingPathComponent("lora")
            .appendingPathComponent("pending")
    }

    init(pendingDirectory: URL) {
        self.pendingDirectory = pendingDirectory
    }

    // MARK: - Write

    /// Creates `pendingDirectory` if missing, then writes `<entry.id>.json` atomically.
    func propose(entry: DPOPendingEntry) throws {
        if !FileManager.default.fileExists(atPath: pendingDirectory.path) {
            try FileManager.default.createDirectory(
                at: pendingDirectory,
                withIntermediateDirectories: true
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(entry)
        let fileURL = pendingDirectory.appendingPathComponent("\(entry.id).json")
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Read

    /// Silently skips files that cannot be decoded.
    func pendingEntries() -> [DPOPendingEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DPOPendingEntry? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(DPOPendingEntry.self, from: data)
                else { return nil }
                return entry
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
