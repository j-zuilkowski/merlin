# Phase diag-06a — Infrastructure Telemetry Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-05b complete: context, planner & critic telemetry instrumented.

New surface introduced in phase diag-06b:
  - `SessionStore.save(_:)` emits:
      `session.save`        — session_id, message_count, duration_ms
  - `HookEngine.runPreToolUse(...)` emits:
      `hook.pre_tool`       — tool_name, decision (allow/deny), duration_ms
  - `HookEngine.runPostToolUse(...)` emits:
      `hook.post_tool`      — tool_name, had_note, duration_ms
  - `HookEngine.runUserPromptSubmit(...)` emits:
      `hook.prompt_submit`  — modified, duration_ms
  - `MCPBridge.call(server:tool:arguments:)` emits:
      `mcp.call.start`      — server, tool
      `mcp.call.complete`   — server, tool, duration_ms, result_bytes
      `mcp.call.error`      — server, tool, error_domain, error_code
  - Process memory sampled periodically via `TelemetryEmitter.shared.emitProcessMemory()`:
      `process.memory`      — rss_mb, vsize_mb

TDD coverage:
  File 1 — SessionStoreTelemetryTests: verify save event fires with correct fields
  File 2 — HookTelemetryTests: verify pre/post hook and prompt events
  File 3 — MCPTelemetryTests: verify MCP call lifecycle events
  File 4 — ProcessMemoryTelemetryTests: verify process memory sampling event

---

## Write to: MerlinTests/Unit/SessionStoreTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SessionStoreTelemetryTests: XCTestCase {

    private var tempTelemetryPath: String!
    private var tempStoreDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempTelemetryPath = "/tmp/merlin-session-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempTelemetryPath)
        tempStoreDir = URL(fileURLWithPath: "/tmp/merlin-session-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempStoreDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempTelemetryPath)
        try? FileManager.default.removeItem(at: tempStoreDir)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempTelemetryPath),
              let content = try? String(contentsOfFile: tempTelemetryPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testSessionSaveEventEmitted() async throws {
        let store = SessionStore(storeDirectory: tempStoreDir)
        var session = Session(title: "Test Session", messages: [])
        session.messages = [
            Message(role: .user, content: .text("hello"), timestamp: Date()),
            Message(role: .assistant, content: .text("hi"), timestamp: Date())
        ]

        try? store.save(session)

        let captured = try await capturedEvents()
        let saves = captured.filter { $0["event"] as? String == "session.save" }
        XCTAssertFalse(saves.isEmpty, "session.save not emitted")
        let d = saves[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["session_id"])
        XCTAssertEqual(d?["message_count"] as? Int, 2)
    }

    func testSessionSaveIncludesDuration() async throws {
        let store = SessionStore(storeDirectory: tempStoreDir)
        let session = Session(title: "T", messages: [])

        try? store.save(session)

        let captured = try await capturedEvents()
        let saves = captured.filter { $0["event"] as? String == "session.save" }
        XCTAssertFalse(saves.isEmpty)
        let ms = saves[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }
}
```

---

## Write to: MerlinTests/Unit/HookTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class HookTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-hook-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testPreToolHookEmitsEvent() async throws {
        // Empty hooks — should still emit allow event
        let engine = HookEngine(hooks: [])
        _ = await engine.runPreToolUse(toolName: "read_file", input: ["path": "/tmp/test.txt"])

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.pre_tool" }
        XCTAssertFalse(events.isEmpty, "hook.pre_tool not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "read_file")
        XCTAssertNotNil(d?["decision"])
        XCTAssertNotNil(d?["duration_ms"])
    }

    func testPostToolHookEmitsEvent() async throws {
        let engine = HookEngine(hooks: [])
        _ = await engine.runPostToolUse(toolName: "shell", result: "exit 0")

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.post_tool" }
        XCTAssertFalse(events.isEmpty, "hook.post_tool not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "shell")
        XCTAssertNotNil(d?["had_note"])
    }

    func testPromptSubmitHookEmitsEvent() async throws {
        let engine = HookEngine(hooks: [])
        _ = await engine.runUserPromptSubmit(prompt: "hello world")

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.prompt_submit" }
        XCTAssertFalse(events.isEmpty, "hook.prompt_submit not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["modified"])
        XCTAssertNotNil(d?["duration_ms"])
    }
}
```

---

## Write to: MerlinTests/Unit/ProcessMemoryTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ProcessMemoryTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-procmem-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testProcessMemoryEventEmittedOnDemand() async throws {
        TelemetryEmitter.shared.emitProcessMemory()
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "process.memory" }
        XCTAssertFalse(events.isEmpty, "process.memory not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["rss_mb"])
        let rss = d?["rss_mb"] as? Double ?? 0
        XCTAssertGreaterThan(rss, 0, "RSS should be > 0 for any live process")
    }

    func testProcessMemoryValuesArePlausible() async throws {
        TelemetryEmitter.shared.emitProcessMemory()
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "process.memory" }
        XCTAssertFalse(events.isEmpty)
        let d = events[0]["data"] as? [String: Any]
        let rss = d?["rss_mb"] as? Double ?? 0
        // Sanity: test process shouldn't use more than 4 GB RSS
        XCTAssertLessThan(rss, 4096)
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
Expected: BUILD FAILED — `session.save`, `hook.pre_tool`, `process.memory` events not yet emitted; `TelemetryEmitter.emitProcessMemory()` not yet defined; `SessionStore.init(directory:)` not yet injectable.

## Commit
```bash
git add MerlinTests/Unit/SessionStoreTelemetryTests.swift \
        MerlinTests/Unit/HookTelemetryTests.swift \
        MerlinTests/Unit/ProcessMemoryTelemetryTests.swift
git commit -m "Phase diag-06a — Infrastructure telemetry tests (failing)"
```
