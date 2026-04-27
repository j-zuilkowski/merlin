# Phase 47b — AI-Generated Memories Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 47a complete: failing tests in place.

New files:
  - `Merlin/Memories/MemoryEntry.swift`
  - `Merlin/Memories/MemoryEngine.swift`
  - `Merlin/UI/Memories/MemoryReviewView.swift` — pending review UI in Settings > Memories

The MemoryEngine uses the session's current provider to call the fastest model (Haiku for Anthropic,
gemini-flash for Google, etc.) with a structured extraction prompt. It never sends verbatim file
content, secret-pattern strings, or raw tool payloads.

---

## Write to: Merlin/Memories/MemoryEntry.swift

```swift
import Foundation

struct MemoryEntry: Sendable {
    var filename: String
    var content: String
}
```

---

## Write to: Merlin/Memories/MemoryEngine.swift

```swift
import Foundation

// Drives AI-generated memory extraction from session transcripts.
// Trigger: idle timeout (configurable, default 5 minutes).
// Output: writes .md files to ~/.merlin/memories/pending/ for user review.
actor MemoryEngine {

    // MARK: - Idle timer state

    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300  // 5 minutes default
    private var onIdleFired: (() -> Void)?

    // MARK: - Public API

    func setOnIdleFired(_ handler: @escaping () -> Void) {
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

    private func scheduleFireTask() {
        idleTask?.cancel()
        let t = timeout
        let handler = onIdleFired
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
                handler?()
            } catch {
                // Cancelled — expected on reset/stop
            }
        }
    }

    // MARK: - Memory generation

    // Returns extracted memory entries from a session transcript.
    // In production: calls the fastest model with an extraction system prompt.
    // Returned content has already been sanitized.
    func generateMemories(from messages: [Message]) async throws -> [MemoryEntry] {
        // Placeholder — full implementation wires into AgenticEngine + provider.
        // The extraction prompt instructs the model to output preferences, conventions,
        // and workflow patterns only — never verbatim file contents or secrets.
        return []
    }

    // MARK: - Pending file I/O

    func writePending(_ entries: [MemoryEntry], to dir: URL) async throws {
        for entry in entries {
            let url = dir.appendingPathComponent(entry.filename)
            try entry.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func pendingMemories(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        return items.filter { $0.pathExtension == "md" }
    }

    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        let dest = acceptedDir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dest)
    }

    func reject(_ url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Content sanitization

    // Removes secret patterns and absolute file paths before writing.
    func sanitize(_ text: String) -> String {
        var result = text
        // Remove API key patterns (sk-ant-*, sk-*, Bearer tokens, etc.)
        let secretPatterns = [
            #"sk-ant-[A-Za-z0-9\-_]{20,}"#,
            #"sk-[A-Za-z0-9]{20,}"#,
            #"Bearer [A-Za-z0-9\-_\.]{20,}"#,
            #"ghp_[A-Za-z0-9]{36}"#,
            #"xoxb-[A-Za-z0-9\-]+"#
        ]
        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range,
                                                        withTemplate: "[REDACTED]")
            }
        }
        // Remove absolute file paths like /Users/... /home/... /tmp/...
        let pathPattern = #"(/Users|/home|/tmp|/var|/etc)/[^\s\"']+"#
        if let regex = try? NSRegularExpression(pattern: pathPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: "[PATH]")
        }
        return result
    }
}
```

---

## Write to: Merlin/UI/Memories/MemoryReviewView.swift

```swift
import SwiftUI

// Shown in Settings > Memories — lists pending AI-generated memories for review.
struct MemoryReviewView: View {

    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()
    private var pendingDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".merlin/memories/pending")
    }
    private var acceptedDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".merlin/memories")
    }

    var body: some View {
        HSplitView {
            List(pendingURLs, id: \.self, selection: $selectedURL) { url in
                Text(url.lastPathComponent)
            }
            .frame(minWidth: 180)

            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(previewContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                HStack {
                    Spacer()
                    Button("Reject") {
                        Task { await rejectSelected() }
                    }
                    .buttonStyle(.bordered)
                    Button("Approve") {
                        Task { await approveSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding([.horizontal, .bottom])
            }
            .frame(minWidth: 300)
        }
        .task { await refresh() }
        .onChange(of: selectedURL) { _, url in
            guard let url else { previewContent = ""; return }
            previewContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private func refresh() async {
        pendingURLs = await engine.pendingMemories(in: pendingDir)
    }

    private func approveSelected() async {
        guard let url = selectedURL else { return }
        try? await engine.approve(url, movingTo: acceptedDir)
        await refresh()
        selectedURL = nil
    }

    private func rejectSelected() async {
        guard let url = selectedURL else { return }
        try? await engine.reject(url)
        await refresh()
        selectedURL = nil
    }
}
```

---

## Integration note

`AgenticEngine` should call `memoryEngine.resetIdleTimer()` on each user message received.
On `SessionManager.close(session:)`, call `memoryEngine.stopIdleTimer()`.
`MemoryEngine.generateMemories(from:)` is called when the idle callback fires; wire the
provider call in a follow-on iteration.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all MemoryEngineTests pass.

## Commit
```bash
git add Merlin/Memories/MemoryEntry.swift \
        Merlin/Memories/MemoryEngine.swift \
        Merlin/UI/Memories/MemoryReviewView.swift
git commit -m "Phase 47b — MemoryEngine (idle timer, pending queue, sanitization)"
```
