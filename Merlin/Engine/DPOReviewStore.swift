import Foundation

enum DPOReviewStoreError: Error {
    case emptyChosen
    case entryNotFound
    case invalidCorpusData
}

actor DPOReviewStore {
    nonisolated let loraRootDirectory: URL
    nonisolated let pendingDirectory: URL
    nonisolated let reviewedCorpusURL: URL

    init(loraRootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".merlin")
        .appendingPathComponent("lora", isDirectory: true)) {
        self.loraRootDirectory = loraRootDirectory
        self.pendingDirectory = loraRootDirectory.appendingPathComponent("pending", isDirectory: true)
        self.reviewedCorpusURL = loraRootDirectory.appendingPathComponent("reviewed.jsonl")
    }

    func loadPendingEntries() -> [DPOPendingEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DPOPendingEntry? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(DPOPendingEntry.self, from: data) else {
                    return nil
                }
                return entry
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func accept(entryID: String, chosen: String) throws {
        let trimmedChosen = chosen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChosen.isEmpty else {
            throw DPOReviewStoreError.emptyChosen
        }

        let pendingEntries = loadPendingEntries()
        guard let entry = pendingEntries.first(where: { $0.id == entryID }) else {
            throw DPOReviewStoreError.entryNotFound
        }

        try persistReviewedEntry(entry, chosen: trimmedChosen)
        try removePendingEntry(entryID: entryID)
    }

    func decline(entryID: String) throws {
        try removePendingEntry(entryID: entryID)
    }

    private func persistReviewedEntry(_ entry: DPOPendingEntry, chosen: String) throws {
        try FileManager.default.createDirectory(at: loraRootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)

        var reviewedEntry = entry
        reviewedEntry.chosen = chosen

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(reviewedEntry)
        let line = String(decoding: data, as: UTF8.self)

        let existing: String
        if let current = try? String(contentsOf: reviewedCorpusURL, encoding: .utf8), !current.isEmpty {
            existing = current.hasSuffix("\n") ? current : current + "\n"
        } else {
            existing = ""
        }

        let output = existing + line + "\n"
        guard let outputData = output.data(using: .utf8) else {
            throw DPOReviewStoreError.invalidCorpusData
        }
        try outputData.write(to: reviewedCorpusURL, options: .atomic)
    }

    private func removePendingEntry(entryID: String) throws {
        let url = pendingDirectory.appendingPathComponent("\(entryID).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
