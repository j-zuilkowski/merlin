# Phase 62b — Memory Generation Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 62a complete: failing MemoryGenerationTests in place.

Implement real LLM-based memory generation in `MemoryEngine`. Add `memoriesEnabled` and
`memoryIdleTimeout` to `AppSettings`. Wire idle callback in `LiveSession`.

---

## Edit: Merlin/Memories/MemoryEngine.swift

Replace the entire file:

```swift
import Foundation

actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?
    private var provider: (any LLMProvider)?

    func setProvider(_ provider: any LLMProvider) {
        self.provider = provider
    }

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
        let nonSystem = messages.filter { $0.role != .system }
        guard !nonSystem.isEmpty else { return [] }

        guard let provider else { return [] }

        let transcript = nonSystem.map { msg -> String in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            switch msg.content {
            case .text(let t): return "\(roleLabel): \(t)"
            case .parts(let parts):
                let text = parts.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: " ")
                return "\(roleLabel): \(text)"
            }
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a memory extraction assistant. Read the conversation transcript and extract \
        concise, reusable facts about the user's preferences, workflow conventions, project \
        patterns, and known pitfalls.

        Rules:
        - Output ONLY bullet lines starting with "- "
        - No verbatim file contents
        - No API keys, tokens, passwords, or secrets
        - No raw tool output or file paths
        - Extract only: preferences, conventions, patterns, pitfalls
        - If there is nothing worth remembering, output nothing
        """

        let request = CompletionRequest(
            model: provider.id,
            messages: [
                Message(role: .system, content: .text(systemPrompt), timestamp: Date()),
                Message(role: .user, content: .text(transcript), timestamp: Date())
            ],
            stream: true,
            maxTokens: 512,
            temperature: 0.3
        )

        let stream = try await provider.complete(request: request)
        var raw = ""
        for try await chunk in stream {
            if let content = chunk.delta?.content {
                raw += content
            }
        }

        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }

        guard !lines.isEmpty else { return [] }

        var entries: [MemoryEntry] = []
        for line in lines {
            let sanitized = await sanitize(line)
            let entry = MemoryEntry(
                filename: "\(UUID().uuidString).md",
                content: sanitized
            )
            entries.append(entry)
        }
        return entries
    }

    func generateAndNotify(
        messages: [Message],
        pendingDir: URL,
        notificationEngine: NotificationEngine
    ) async throws {
        let entries = try await generateMemories(from: messages)
        guard !entries.isEmpty else { return }
        try await writePending(entries, to: pendingDir)
        await notificationEngine.post(
            title: "Memories ready",
            body: "\(entries.count) memory \(entries.count == 1 ? "suggestion" : "suggestions") ready for review.",
            identifier: "memories-\(UUID().uuidString)"
        )
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
                guard let self else { return }
                await self.fireIdle()
            } catch {
                return
            }
        }
    }

    private func fireIdle() async {
        let callback = onIdleFired
        await MainActor.run { callback?() }
    }
}
```

---

## Edit: Merlin/Config/AppSettings.swift

Add two published properties after `maxSubagentDepth`:

```swift
    @Published var memoriesEnabled: Bool = false
    @Published var memoryIdleTimeout: TimeInterval = 300
```

Add to `ConfigFile` struct:

```swift
        var memoriesEnabled: Bool?
        var memoryIdleTimeout: TimeInterval?
```

Add CodingKeys:

```swift
            case memoriesEnabled = "memories_enabled"
            case memoryIdleTimeout = "memory_idle_timeout"
```

Add to `load(from:)`:

```swift
        if let value = config.memoriesEnabled { memoriesEnabled = value }
        if let value = config.memoryIdleTimeout { memoryIdleTimeout = value }
```

Add to `save(to:)` after the xcalibre_token block:

```swift
        if memoriesEnabled {
            lines.append("memories_enabled = true")
            lines.append("memory_idle_timeout = \(memoryIdleTimeout)")
        }
```

---

## Edit: Merlin/Sessions/LiveSession.swift

Add memory engine wiring in `init(projectRef:)`. After the existing MCP Task block, append:

```swift
        let memoryEngine = MemoryEngine()
        Task {
            await memoryEngine.setProvider(appState.engine.flashProvider)
            if AppSettings.shared.memoriesEnabled {
                let timeout = AppSettings.shared.memoryIdleTimeout
                let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
                let pendingDir = URL(fileURLWithPath: "\(home)/.merlin/memories/pending")
                let notificationEngine = NotificationEngine()
                await memoryEngine.setOnIdleFired { [weak appState] in
                    guard let appState else { return }
                    Task {
                        let messages = await appState.engine.contextManager.messages
                        try? await memoryEngine.generateAndNotify(
                            messages: messages,
                            pendingDir: pendingDir,
                            notificationEngine: notificationEngine
                        )
                    }
                }
                await memoryEngine.startIdleTimer(timeout: timeout)
            }
        }
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'MemoryGeneration.*passed|MemoryGeneration.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `TEST BUILD SUCCEEDED`; all MemoryGenerationTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Memories/MemoryEngine.swift \
        Merlin/Config/AppSettings.swift \
        Merlin/Sessions/LiveSession.swift
git commit -m "Phase 62b — MemoryEngine LLM generation + AppSettings.memoriesEnabled"
```
