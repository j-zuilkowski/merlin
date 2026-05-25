# Task 165a — DPO Pair Collection Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 164b complete: critic retry loop in AgenticEngine; `criticEnabled`/`maxCriticRetries` in AppSettings.

New surface introduced in task 165b:
  - `DPOPendingEntry` struct — prompt, chosen, rejected, modelID, timestamp; `Codable + Sendable`
  - `DPOQueue` actor — `propose(entry:)` writes JSON to `~/.merlin/lora/pending/<uuid>.json`,
    `pendingEntries()` loads and returns all pending entries
  - AgenticEngine `proposeDPOPairIfNeeded(prompt:response:modelID:)` — called at end of turn;
    proposes a DPO pair when `OutcomeSignals.userCorrectedNextTurn == true` (heuristic: next
    message starts with a correction keyword list) and session had no tool errors
  - `AppSettings.dpoEnabled: Bool` — default `true`; TOML key `dpo_enabled`

TDD coverage:
  File 1 — DPOQueueTests: DPOPendingEntry encoding, propose writes file, pendingEntries loads
    all files, directory is created on first propose
  File 2 — DPOAutoFilterTests: engine skips proposal when dpoEnabled = false; skips when
    userCorrectedNextTurn = false; proposes when userCorrectedNextTurn = true

---

## Write to: MerlinTests/Unit/DPOQueueTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for Task 165 — DPOQueue pending entry persistence
//
// Covers:
//   - DPOPendingEntry is Codable round-trips correctly
//   - DPOQueue.propose(entry:) writes a JSON file to the pending dir
//   - DPOQueue.pendingEntries() loads all entries in the directory
//   - Pending directory is created automatically on first propose
//   - Multiple entries are stored independently (separate UUID filenames)

final class DPOQueueTests: XCTestCase {

    private var tmpDir: URL!
    private var queue: DPOQueue!

    override func setUp() async throws {
        tmpDir = URL(fileURLWithPath: "/tmp/dpo-queue-tests-\(UUID().uuidString)")
        queue = DPOQueue(pendingDirectory: tmpDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - DPOPendingEntry Codable

    func testDPOPendingEntryCodableRoundTrip() throws {
        let entry = DPOPendingEntry(
            prompt: "Refactor AuthGate to use async/await",
            chosen: "Here is the corrected async/await version.",
            rejected: "Here is the original synchronous version.",
            modelID: "lmstudio:qwen/qwen3-27b",
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DPOPendingEntry.self, from: data)

        XCTAssertEqual(decoded.prompt, entry.prompt)
        XCTAssertEqual(decoded.chosen, entry.chosen)
        XCTAssertEqual(decoded.rejected, entry.rejected)
        XCTAssertEqual(decoded.modelID, entry.modelID)
        XCTAssertEqual(decoded.timestamp, entry.timestamp)
    }

    func testDPOPendingEntryHasUUID() {
        let e1 = DPOPendingEntry(
            prompt: "p", chosen: "c", rejected: "r",
            modelID: "m", timestamp: Date()
        )
        let e2 = DPOPendingEntry(
            prompt: "p", chosen: "c", rejected: "r",
            modelID: "m", timestamp: Date()
        )
        XCTAssertNotEqual(e1.id, e2.id,
                          "Each DPOPendingEntry must have a unique UUID")
    }

    // MARK: - propose writes a file

    func testProposeCreatesFileInPendingDirectory() async throws {
        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1,
                       "propose must create exactly one file in the pending directory")
    }

    func testProposeCreatesDirectoryAutomatically() async throws {
        // Directory does not exist yet — propose must create it
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.path),
                       "Precondition: pending dir must not exist before first propose")

        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path),
                      "propose must create the pending directory if it does not exist")
    }

    func testProposeWritesValidJSON() async throws {
        let entry = DPOPendingEntry(
            prompt: "Fix the bug", chosen: "Fixed version", rejected: "Broken version",
            modelID: "model-x", timestamp: Date(timeIntervalSince1970: 2_000_000)
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        guard let file = files.first else {
            XCTFail("No file created"); return
        }
        let data = try Data(contentsOf: file)
        let decoded = try JSONDecoder().decode(DPOPendingEntry.self, from: data)

        XCTAssertEqual(decoded.prompt, entry.prompt)
        XCTAssertEqual(decoded.chosen, entry.chosen)
        XCTAssertEqual(decoded.rejected, entry.rejected)
    }

    func testProposeFilenameIsUUIDDotJSON() async throws {
        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        guard let file = files.first else {
            XCTFail("No file created"); return
        }
        let name = file.lastPathComponent
        XCTAssertTrue(name.hasSuffix(".json"),
                      "Pending file must have .json extension, got: \(name)")
        // Filename (without .json) must be a valid UUID
        let uuidPart = String(name.dropLast(5)) // drop ".json"
        XCTAssertNotNil(UUID(uuidString: uuidPart),
                        "Filename (sans .json) must be a valid UUID, got: \(uuidPart)")
    }

    func testProposeMultipleEntriesCreatesMultipleFiles() async throws {
        for i in 1...3 {
            let entry = DPOPendingEntry(
                prompt: "task \(i)", chosen: "good \(i)", rejected: "bad \(i)",
                modelID: "model-a", timestamp: Date()
            )
            try await queue.propose(entry: entry)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 3,
                       "Three separate propose calls must produce three separate files")
    }

    // MARK: - pendingEntries loads all files

    func testPendingEntriesReturnsEmptyWhenDirectoryEmpty() async throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "pendingEntries must return empty array when directory contains no files")
    }

    func testPendingEntriesLoadsAllProposedEntries() async throws {
        let e1 = DPOPendingEntry(prompt: "p1", chosen: "c1", rejected: "r1", modelID: "m", timestamp: Date())
        let e2 = DPOPendingEntry(prompt: "p2", chosen: "c2", rejected: "r2", modelID: "m", timestamp: Date())
        try await queue.propose(entry: e1)
        try await queue.propose(entry: e2)

        let loaded = await queue.pendingEntries()
        XCTAssertEqual(loaded.count, 2,
                       "pendingEntries must load all proposed files")
        let prompts = Set(loaded.map(\.prompt))
        XCTAssertEqual(prompts, Set(["p1", "p2"]))
    }

    func testPendingEntriesSkipsMalformedFiles() async throws {
        // Write a valid entry
        let entry = DPOPendingEntry(prompt: "task", chosen: "ok", rejected: "bad", modelID: "m", timestamp: Date())
        try await queue.propose(entry: entry)
        // Write a garbage file
        let garbageURL = tmpDir.appendingPathComponent("\(UUID().uuidString).json")
        try "not valid json {{{".write(to: garbageURL, atomically: true, encoding: .utf8)

        let loaded = await queue.pendingEntries()
        XCTAssertEqual(loaded.count, 1,
                       "pendingEntries must silently skip malformed JSON files")
    }
}
```

---

## Write to: MerlinTests/Unit/DPOAutoFilterTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for Task 165 — DPO auto-filter: what sessions get proposed
//
// Covers:
//   - AppSettings.dpoEnabled default is true
//   - Engine does not propose DPO entry when dpoEnabled = false
//   - Engine does not propose DPO entry when no correction detected on follow-up turn
//   - Engine proposes DPO entry when follow-up message begins with a correction keyword

@MainActor
final class DPOAutoFilterTests: XCTestCase {

    // MARK: - AppSettings defaults

    func testDPOEnabledDefaultIsTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.dpoEnabled,
                      "dpoEnabled must default to true")
    }

    // MARK: - DPO disabled

    func testNoDPOProposalWhenDPODisabled() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-disabled-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settings = AppSettings.shared
        let originalEnabled = settings.dpoEnabled
        settings.dpoEnabled = false
        defer { settings.dpoEnabled = originalEnabled }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        // First turn: get a response
        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Second turn: a correction
        _ = await collectEvents(engine.send(userMessage: "that's wrong, please fix the return type"))

        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "No DPO entry must be proposed when dpoEnabled = false")
    }

    // MARK: - Correction detection

    func testNoDPOProposalForNonCorrectionFollowUp() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-nocorrect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Neutral follow-up — not a correction
        _ = await collectEvents(engine.send(userMessage: "what other approaches exist?"))

        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "No DPO entry must be proposed when follow-up is not a correction")
    }

    func testDPOEntryProposedWhenFollowUpBeginsWithCorrectionKeyword() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-correct-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Correction follow-up — triggers DPO proposal for the previous turn
        _ = await collectEvents(engine.send(userMessage: "that's wrong, the return type should be String not Int"))

        let entries = await queue.pendingEntries()
        XCTAssertFalse(entries.isEmpty,
                       "DPO entry must be proposed when follow-up begins with a correction keyword")
    }

    func testDPOEntryContainsOriginalPromptAndResponse() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-content-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        _ = await collectEvents(engine.send(userMessage: "that's wrong, please fix it"))

        let entries = await queue.pendingEntries()
        guard let entry = entries.first else {
            XCTFail("Expected a DPO entry"); return
        }
        XCTAssertFalse(entry.prompt.isEmpty,
                       "DPO entry prompt must not be empty")
        XCTAssertFalse(entry.rejected.isEmpty,
                       "DPO entry rejected (original model response) must not be empty")
    }
}

// MARK: - Helpers

@MainActor
private func makeDPOEngine(dpoQueue: DPOQueue) -> AgenticEngine {
    let executeProvider = ShortTextProvider(id: "execute-dpo-\(UUID().uuidString)")
    let registry = ProviderRegistry()
    registry.add(executeProvider)

    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-dpo-filter-\(UUID().uuidString).json"),
        presenter: NullAuthPresenter()
    )
    let engine = AgenticEngine(
        slotAssignments: [.execute: executeProvider.id],
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager()
    )
    engine.dpoQueue = dpoQueue
    return engine
}

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

// MARK: - Test doubles

/// Provider that returns a short deterministic text response suitable for
/// DPO pair testing (no tool calls, critic does not fire).
private final class ShortTextProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    init(id: String) { self.id = id }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let response = "func add(_ a: Int, _ b: Int) -> Int { return a + b }"
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: response, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED with errors naming `DPOPendingEntry`, `DPOQueue`, `dpoEnabled`, `dpoQueue`.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/DPOQueueTests.swift MerlinTests/Unit/DPOAutoFilterTests.swift
git commit -m "Task 165a — DPOQueueTests + DPOAutoFilterTests (failing)"
```
