import Foundation

// MARK: - DPOPendingEntry

/// A single DPO (Direct Preference Optimization) training pair awaiting user review.
/// Stored as JSON at `~/.merlin/lora/pending/<uuid>.json`.
///
/// - `prompt`    — the user message that triggered the model response
/// - `chosen`    — the preferred (user-corrected) response; empty until user fills in via review queue
/// - `rejected`  — the original model response that was corrected
/// - `modelID`   — provider model identifier at time of generation
/// - `timestamp` — when the pair was captured
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

/// Manages the `~/.merlin/lora/pending/` queue of proposed DPO training pairs.
///
/// Each entry is stored as a separate JSON file named `<uuid>.json`.
/// This mirrors the memories `pending/` pattern — items wait for user approval
/// before entering the training corpus.
actor DPOQueue {

    private let pendingDirectory: URL

    /// Default init using `~/.merlin/lora/pending/`
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.pendingDirectory = home
            .appendingPathComponent(".merlin")
            .appendingPathComponent("lora")
            .appendingPathComponent("pending")
    }

    /// Test init accepting an arbitrary directory.
    init(pendingDirectory: URL) {
        self.pendingDirectory = pendingDirectory
    }

    // MARK: - Write

    /// Persist `entry` as `<entry.id>.json` in the pending directory.
    /// Creates the directory if it does not exist.
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

    /// Load and return all valid pending entries from the directory.
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
