// StagingBuffer — intercepts agent file mutations for human review before they hit disk.
//
// ToolRouter writes proposed changes here when stagingBuffer is non-nil and the
// permission mode is Ask or Plan. The DiffPane view reads pendingChanges (via
// StagingBufferWrapper) and lets the user accept or reject each one individually
// or in bulk.
//
// See: Developer Manual § "Tool System → Staging Buffer"
import Foundation

enum ChangeKind: String, Codable, Sendable {
    case write
    case create
    case delete
    case move
}

struct StagedChange: Identifiable, Sendable {
    var id: UUID = UUID()
    var path: String
    var kind: ChangeKind
    var before: String?
    var after: String?
    var destinationPath: String?
    var comments: [DiffComment] = []
}

struct StagingEntry: Identifiable, Sendable, Equatable {
    var id = UUID()
    var path: String
    var operation: String
}

actor StagingBuffer {
    private var history: [StagingEntry] = []
    private(set) var pendingChanges: [StagedChange] = []
    // MARK: - Session outcome counters
    // Reset at the start of each runLoop turn via resetSessionCounts().
    // Read by AgenticEngine at session end to populate OutcomeSignals.
    private(set) var acceptedCount: Int = 0
    private(set) var rejectedCount: Int = 0
    private(set) var editedOnAcceptCount: Int = 0

    func entries() -> [StagingEntry] {
        history
    }

    func resetSessionCounts() {
        acceptedCount = 0
        rejectedCount = 0
        editedOnAcceptCount = 0
    }

    func record(_ entry: StagingEntry) {
        history.append(entry)
    }

    func stage(_ change: StagedChange) {
        pendingChanges.append(change)
        history.append(StagingEntry(path: change.path, operation: change.kind.rawValue))
    }

    func addComment(_ comment: DiffComment, toChange id: UUID) {
        guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
        pendingChanges[index].comments.append(comment)
    }

    func commentsAsAgentMessage(_ changeIDs: [UUID]) -> String {
        var parts: [String] = [
            "I've reviewed the staged changes and left inline comments. Please revise accordingly:\n"
        ]

        for id in changeIDs {
            guard let change = pendingChanges.first(where: { $0.id == id }),
                  !change.comments.isEmpty else { continue }
            let filename = (change.path as NSString).lastPathComponent
            parts.append("**\(filename)** (`\(change.path)`):")
            for comment in change.comments.sorted(by: { $0.lineIndex < $1.lineIndex }) {
                parts.append("  - Line \(comment.lineIndex): \(comment.body)")
            }
        }

        return parts.joined(separator: "\n")
    }

    func accept(_ id: UUID) async throws {
        guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
        let change = pendingChanges[index]
        try applyChange(change)
        pendingChanges.remove(at: index)
        removeHistoryEntry(matching: change)
        acceptedCount += 1
        if !change.comments.isEmpty { editedOnAcceptCount += 1 }
    }

    func reject(_ id: UUID) {
        guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
        let change = pendingChanges.remove(at: index)
        removeHistoryEntry(matching: change)
        rejectedCount += 1
    }

    func acceptAll() async throws {
        for change in pendingChanges {
            try applyChange(change)
            removeHistoryEntry(matching: change)
            acceptedCount += 1
            if !change.comments.isEmpty { editedOnAcceptCount += 1 }
        }
        pendingChanges.removeAll()
    }

    func rejectAll() {
        rejectedCount += pendingChanges.count
        for change in pendingChanges {
            removeHistoryEntry(matching: change)
        }
        pendingChanges.removeAll()
    }

    private func applyChange(_ change: StagedChange) throws {
        let fm = FileManager.default
        switch change.kind {
        case .write, .create:
            let content = change.after ?? ""
            let dir = (change.path as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: change.path, atomically: true, encoding: .utf8)
        case .delete:
            if fm.fileExists(atPath: change.path) {
                try fm.removeItem(atPath: change.path)
            }
        case .move:
            guard let dest = change.destinationPath else {
                throw CocoaError(.fileNoSuchFile)
            }
            try fm.createDirectory(
                atPath: (dest as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try fm.moveItem(atPath: change.path, toPath: dest)
        }
    }

    private func removeHistoryEntry(matching change: StagedChange) {
        history.removeAll { entry in
            entry.path == change.path && entry.operation == change.kind.rawValue
        }
    }
}
