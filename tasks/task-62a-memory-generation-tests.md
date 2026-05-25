# Phase 62a — Memory Generation Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 61b complete: image → vision description.

New surface introduced in phase 62b:
  - `MemoryEngine.setProvider(_ provider: any LLMProvider)` — injects provider for generation
  - `MemoryEngine.generateMemories(from messages: [Message])` — real LLM single-turn call;
    returns `[MemoryEntry]` parsed from bullet lines; sanitized
  - `MemoryEngine.generateAndNotify(messages:pendingDir:notificationEngine:)` — writes files
    then posts a UNUserNotification
  - `AppSettings.memoriesEnabled: Bool` (default false)
  - `AppSettings.memoryIdleTimeout: TimeInterval` (default 300)

TDD coverage:
  File 1 — MemoryGenerationTests: provider wired correctly, entries parsed, sanitized,
            empty transcript returns empty, generateAndNotify writes files

---

## Write to: MerlinTests/Unit/MemoryGenerationTests.swift

```swift
import XCTest
@testable import Merlin

final class MemoryGenerationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("memory-gen-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - generateMemories

    func testGenerateMemoriesReturnsParsedEntries() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: """
        - User prefers bullet points over paragraphs
        - Always run tests before committing
        - Project uses SWIFT_STRICT_CONCURRENCY=complete
        """)
        await engine.setProvider(mock)

        let messages = [
            Message(role: .user, content: .text("How do I run tests?"), timestamp: Date()),
            Message(role: .assistant, content: .text("Use xcodebuild -scheme MerlinTests test"), timestamp: Date())
        ]

        let entries = try await engine.generateMemories(from: messages)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].content.contains("bullet points"))
        XCTAssertTrue(entries[1].content.contains("run tests"))
    }

    func testGenerateMemoriesIgnoresSystemMessages() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "- Prefers dark mode")
        await engine.setProvider(mock)

        let messages = [
            Message(role: .system, content: .text("[Project instructions]\n..."), timestamp: Date()),
            Message(role: .user, content: .text("What theme do you recommend?"), timestamp: Date()),
            Message(role: .assistant, content: .text("Dark mode."), timestamp: Date())
        ]

        let entries = try await engine.generateMemories(from: messages)
        XCTAssertFalse(entries.isEmpty)
    }

    func testGenerateMemoriesEmptyTranscriptReturnsEmpty() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "")
        await engine.setProvider(mock)

        let entries = try await engine.generateMemories(from: [])
        XCTAssertTrue(entries.isEmpty)
    }

    func testGenerateMemoriesOnlySystemReturnsEmpty() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "- something")
        await engine.setProvider(mock)

        let messages = [
            Message(role: .system, content: .text("system prompt"), timestamp: Date())
        ]
        let entries = try await engine.generateMemories(from: messages)
        XCTAssertTrue(entries.isEmpty, "Only system messages should produce no entries")
    }

    func testGenerateMemoriesFilenamesAreUUIDs() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "- User likes concise answers")
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("hi"), timestamp: Date())]
        let entries = try await engine.generateMemories(from: messages)
        for entry in entries {
            let nameWithoutExt = (entry.filename as NSString).deletingPathExtension
            XCTAssertNotNil(UUID(uuidString: nameWithoutExt), "Filename should be a UUID: \(entry.filename)")
            XCTAssertTrue(entry.filename.hasSuffix(".md"))
        }
    }

    func testGenerateMemoriesSanitizesSecrets() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "- Token sk-ant-abc123xyz is the key")
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("hi"), timestamp: Date())]
        let entries = try await engine.generateMemories(from: messages)
        for entry in entries {
            XCTAssertFalse(entry.content.contains("sk-ant-abc123xyz"), "Secrets should be redacted")
        }
    }

    // MARK: - generateAndNotify

    func testGenerateAndNotifyWritesFilesToPendingDir() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "- User prefers TDD")
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("test"), timestamp: Date())]
        let notificationEngine = NotificationEngine()

        try await engine.generateAndNotify(
            messages: messages,
            pendingDir: tempDir,
            notificationEngine: notificationEngine
        )

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty, "At least one memory file should be written")
        XCTAssertTrue(files.allSatisfy { $0.pathExtension == "md" })
    }

    func testGenerateAndNotifyEmptyTranscriptWritesNothing() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider(response: "")
        await engine.setProvider(mock)

        let notificationEngine = NotificationEngine()
        try await engine.generateAndNotify(messages: [], pendingDir: tempDir, notificationEngine: notificationEngine)

        let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(files.isEmpty)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` — `setProvider`, `generateAndNotify` not yet on `MemoryEngine`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/MemoryGenerationTests.swift
git commit -m "Phase 62a — MemoryGenerationTests (failing)"
```
