# Phase 122a — Memory Xcalibre Index Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 121b complete: LoRA settings UI in place. 653 tests passing.

New surface introduced in phase 122b:
  - `MemoryEngine.setXcalibreClient(_ client: any XcalibreClientProtocol)` — injects xcalibre client
  - `MemoryEngine.approve(_:movingTo:)` — extended to call `writeMemoryChunk` after moving the file

Accepted AI-generated memories currently only land in `~/.merlin/memories/` and are injected as
a verbatim system prompt block. Phase 122 adds a second path: on approval the content is also
written to xcalibre-server as a `"factual"` chunk so it participates in RAG queries alongside
per-turn episodic memory.

`XcalibreClientProtocol` already exists at:
  `Merlin/Engine/Protocols/XcalibreClientProtocol.swift`

`MemoryEngine.approve(_:movingTo:)` already exists in:
  `Merlin/Memories/MemoryEngine.swift`

TDD coverage:
  File 1 — MerlinTests/Unit/MemoryXcalibreIndexTests.swift:
    - testSetXcalibreClientCompiles — verifies `setXcalibreClient` exists on the actor
    - testApproveCallsXcalibreWriteWithFileContent — spy captures content passed to writeMemoryChunk
    - testApproveChunkTypeIsFactual — verifies chunkType is "factual" (not "episodic")
    - testApproveTagsIncludeSessionMemory — verifies tags contain "session-memory"
    - testApproveNilClientSucceeds — no client set; approve still moves the file
    - testXcalibreWriteFailureDoesNotBlockFileMove — spy returns nil; file still moves

---

## Write to: MerlinTests/Unit/MemoryXcalibreIndexTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Spy

private final class SpyXcalibreClient: XcalibreClientProtocol, @unchecked Sendable {
    var writeCallCount = 0
    var lastText: String?
    var lastChunkType: String?
    var lastTags: [String] = []
    var writeReturnValue: String? = "chunk-id-1"

    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] { [] }
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] { [] }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String? {
        writeCallCount += 1
        lastText = text
        lastChunkType = chunkType
        lastTags = tags
        return writeReturnValue
    }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
}

// MARK: - Tests

final class MemoryXcalibreIndexTests: XCTestCase {

    // MARK: Helpers

    private var tmpDir: URL!
    private var pendingDir: URL!
    private var acceptedDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MemoryXcalibreIndexTests-\(UUID().uuidString)")
        pendingDir = tmpDir.appendingPathComponent("pending")
        acceptedDir = tmpDir.appendingPathComponent("accepted")
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func makePendingFile(content: String = "- Prefer async/await over callbacks") -> URL {
        let url = pendingDir.appendingPathComponent("\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func testSetXcalibreClientCompiles() async {
        // Verifies the method exists on the actor — fails to build without phase 122b.
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)
        // No assertion needed — compilation is the test.
    }

    func testApproveCallsXcalibreWriteWithFileContent() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let content = "- Always use actors for shared mutable state"
        let url = makePendingFile(content: content)

        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.writeCallCount, 1)
        XCTAssertEqual(spy.lastText, content)
    }

    func testApproveChunkTypeIsFactual() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.lastChunkType, "factual")
    }

    func testApproveTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertTrue(spy.lastTags.contains("session-memory"),
                      "Expected tags to contain 'session-memory', got \(spy.lastTags)")
    }

    func testApproveNilClientSucceeds() async throws {
        // No xcalibre client set — approve must still move the file.
        let engine = MemoryEngine()
        // Do NOT call setXcalibreClient

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even with no xcalibre client")
    }

    func testXcalibreWriteFailureDoesNotBlockFileMove() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        spy.writeReturnValue = nil          // simulate xcalibre unavailable / write failed
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even when xcalibre write returns nil")
        XCTAssertEqual(spy.writeCallCount, 1,
                       "writeMemoryChunk should have been attempted regardless of return value")
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
Expected: **BUILD FAILED** — `MemoryEngine` has no `setXcalibreClient` method.

## Commit
```bash
git add MerlinTests/Unit/MemoryXcalibreIndexTests.swift
git commit -m "Phase 122a — MemoryXcalibreIndexTests (failing)"
```
