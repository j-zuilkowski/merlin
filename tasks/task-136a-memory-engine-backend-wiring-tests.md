# Phase 136a — MemoryEngine Backend Wiring Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 135b complete: LocalVectorPlugin, EmbeddingProviderProtocol in place.

New surface introduced in phase 136b:
  - `MemoryEngine.setMemoryBackend(_ backend: any MemoryBackendPlugin)` replaces
    `setXcalibreClient`. The old method is removed.
  - `MemoryEngine.approve(_:movingTo:)` writes a `MemoryChunk` (chunkType: "factual",
    tags: ["session-memory"]) to the backend after moving the file.
  - `XcalibreClientProtocol` and xcalibre write are fully removed from MemoryEngine.

TDD coverage:
  File: MerlinTests/Unit/MemoryEngineBackendWiringTests.swift
    - approve writes a factual chunk to the injected backend
    - approved chunk content matches the file contents
    - approved chunk tags include "session-memory"
    - approve with no backend (NullMemoryPlugin) does not throw
    - setXcalibreClient no longer exists on MemoryEngine (compile-time check via absence)
    - reject does not write to backend

  File: TestHelpers/CapturingMemoryBackend.swift
    - CapturingMemoryBackend: MemoryBackendPlugin
      Captures all writes; search returns []; delete is no-op.

---

## Write to: TestHelpers/CapturingMemoryBackend.swift

```swift
import Foundation
@testable import Merlin

/// Test double that records every chunk passed to `write(_:)`.
/// Used to assert that engines write correct chunks without a real database.
actor CapturingMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "capturing"
    nonisolated let displayName = "Capturing (test)"

    private(set) var writtenChunks: [MemoryChunk] = []

    func write(_ chunk: MemoryChunk) async throws {
        writtenChunks.append(chunk)
    }

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] { [] }

    func delete(id: String) async throws {}
}
```

---

## Write to: MerlinTests/Unit/MemoryEngineBackendWiringTests.swift

```swift
import XCTest
@testable import Merlin

final class MemoryEngineBackendWiringTests: XCTestCase {

    private let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())

    // MARK: - Helpers

    private func writeTmpFile(name: String, content: String) throws -> URL {
        let dir = tmpDir.appendingPathComponent("mebt-pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func acceptedDir() -> URL {
        tmpDir.appendingPathComponent("mebt-accepted-\(UUID().uuidString)")
    }

    // MARK: - Tests

    func testApproveWritesFactualChunkToBackend() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "fact.md", content: "The user prefers dark mode.")
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].chunkType, "factual")
    }

    func testApproveChunkContentMatchesFile() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let content = "User always runs tests before committing."
        let file = try writeTmpFile(name: "pref.md", content: content)
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertEqual(written.first?.content, content)
    }

    func testApproveChunkTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "tag.md", content: "tag test")
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertTrue(written.first?.tags.contains("session-memory") == true)
    }

    func testApproveWithNullBackendDoesNotThrow() async throws {
        let engine = MemoryEngine()
        await engine.setMemoryBackend(NullMemoryPlugin())

        let file = try writeTmpFile(name: "null.md", content: "null backend test")
        // Must not throw
        try await engine.approve(file, movingTo: acceptedDir())
    }

    func testRejectDoesNotWriteToBackend() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "reject.md", content: "should be rejected")
        try await engine.reject(file)

        let written = await backend.writtenChunks
        XCTAssertTrue(written.isEmpty)
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
Expected: BUILD FAILED — `MemoryEngine.setMemoryBackend(_:)` is undefined;
`CapturingMemoryBackend` is new (compile error on test target only).

## Commit
```bash
git add MerlinTests/Unit/MemoryEngineBackendWiringTests.swift
git add TestHelpers/CapturingMemoryBackend.swift
git commit -m "Phase 136a — MemoryEngine backend wiring tests (failing)"
```
