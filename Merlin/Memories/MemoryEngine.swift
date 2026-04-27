import Foundation

actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?

    func setOnIdleFired(_ handler: @escaping @Sendable () -> Void) {
        onIdleFired = handler
    }

    func startIdleTimer(timeout: TimeInterval) {
        self.timeout = timeout
        scheduleFireTask()
    }

    func resetIdleTimer() {
        scheduleFireTask()
    }

    func stopIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
    }

    func generateMemories(from messages: [Message]) async throws -> [MemoryEntry] {
        _ = messages
        return []
    }

    func writePending(_ entries: [MemoryEntry], to dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for entry in entries {
            let url = dir.appendingPathComponent(entry.filename)
            try entry.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func pendingMemories(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "md" }
    }

    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }

    func reject(_ url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    func sanitize(_ text: String) async -> String {
        var result = text
        let secretPatterns = [
            #"sk-ant-[A-Za-z0-9\-_]+"#,
            #"sk-[A-Za-z0-9]{8,}"#,
            #"Bearer [A-Za-z0-9\-_\.]{8,}"#,
            #"ghp_[A-Za-z0-9]{20,}"#,
            #"xoxb-[A-Za-z0-9\-]+"#
        ]

        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED]")
            }
        }

        let pathPattern = #"(/Users|/home|/tmp|/var|/etc)/[^\s\"']+"#
        if let regex = try? NSRegularExpression(pattern: pathPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[PATH]")
        }

        return result
    }

    private func scheduleFireTask() {
        idleTask?.cancel()
        let timeout = timeout
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                guard let self else {
                    return
                }
                await self.fireIdle()
            } catch {
                return
            }
        }
    }

    private func fireIdle() async {
        let callback = onIdleFired
        await MainActor.run {
            callback?()
        }
    }
}
