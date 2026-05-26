# Task 63a — Memory Injection Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 62b complete: MemoryEngine real LLM generation + AppSettings fields.

New surface introduced in task 63b:
  - `ConstitutionLoader.memoriesBlock(acceptedDir:)` — reads *.md files from dir, wraps in
    `[Memories]…[/Memories]` block; returns empty string when dir is empty or missing
  - `AgenticEngine.memoriesContent: String` — injected into system prompt after constitutionContent
  - `AgenticEngine.buildSystemPrompt()` — now includes memoriesContent block when non-empty

TDD coverage:
  File 1 — MemoryInjectionTests: memoriesBlock output, empty dir, AgenticEngine prompt order

---

## Write to: MerlinTests/Unit/MemoryInjectionTests.swift

```swift
import XCTest
@testable import Merlin

final class MemoryInjectionTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mem-inject-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - ConstitutionLoader.memoriesBlock

    func testMemoriesBlockWrapsContent() throws {
        let file1 = tempDir.appendingPathComponent("a.md")
        try "- User prefers bullet points".write(to: file1, atomically: true, encoding: .utf8)

        let block = ConstitutionLoader.memoriesBlock(acceptedDir: tempDir.path)
        XCTAssertTrue(block.hasPrefix("[Memories]"), "Block should open with [Memories]")
        XCTAssertTrue(block.hasSuffix("[/Memories]"), "Block should close with [/Memories]")
        XCTAssertTrue(block.contains("bullet points"))
    }

    func testMemoriesBlockCombinesMultipleFiles() throws {
        try "- Pref A".write(to: tempDir.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        try "- Pref B".write(to: tempDir.appendingPathComponent("2.md"), atomically: true, encoding: .utf8)

        let block = ConstitutionLoader.memoriesBlock(acceptedDir: tempDir.path)
        XCTAssertTrue(block.contains("Pref A"))
        XCTAssertTrue(block.contains("Pref B"))
    }

    func testMemoriesBlockEmptyDirReturnsEmpty() {
        let block = ConstitutionLoader.memoriesBlock(acceptedDir: tempDir.path)
        XCTAssertTrue(block.isEmpty, "Empty memories dir should return empty string")
    }

    func testMemoriesBlockMissingDirReturnsEmpty() {
        let missing = tempDir.appendingPathComponent("does-not-exist").path
        let block = ConstitutionLoader.memoriesBlock(acceptedDir: missing)
        XCTAssertTrue(block.isEmpty)
    }

    func testMemoriesBlockIgnoresNonMdFiles() throws {
        try "- Real memory".write(to: tempDir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let block = ConstitutionLoader.memoriesBlock(acceptedDir: tempDir.path)
        XCTAssertTrue(block.contains("Real memory"))
        XCTAssertFalse(block.contains("ignored"))
    }

    // MARK: - AgenticEngine system prompt order

    @MainActor
    func testBuildSystemPromptIncludesMemoriesAfterConstitution() {
        let engine = EngineFactory.makeEngine()
        engine.constitutionContent = "[Project instructions]\nUse TDD.\n[/Project instructions]"
        engine.memoriesContent = "[Memories]\n- User likes brevity\n[/Memories]"

        // Trigger a send to get the messages-with-system prepended
        let messages = engine.messagesWithSystem(
            [Message(role: .user, content: .text("hi"), timestamp: Date())]
        )
        let systemText = messages.first.flatMap { msg -> String? in
            guard msg.role == .system, case .text(let t) = msg.content else { return nil }
            return t
        } ?? ""

        XCTAssertTrue(systemText.contains("[Project instructions]"), "constitution.md content should be present")
        XCTAssertTrue(systemText.contains("[Memories]"), "Memories block should be present")

        let claudeRange = systemText.range(of: "[Project instructions]")!
        let memoriesRange = systemText.range(of: "[Memories]")!
        XCTAssertLessThan(claudeRange.lowerBound, memoriesRange.lowerBound,
                          "constitution.md content should appear before memories")
    }

    @MainActor
    func testBuildSystemPromptNoMemoriesOmitsBlock() {
        let engine = EngineFactory.makeEngine()
        engine.constitutionContent = "[Project instructions]\nUse TDD.\n[/Project instructions]"
        engine.memoriesContent = ""

        let messages = engine.messagesWithSystem(
            [Message(role: .user, content: .text("hi"), timestamp: Date())]
        )
        let systemText = messages.first.flatMap { msg -> String? in
            guard msg.role == .system, case .text(let t) = msg.content else { return nil }
            return t
        } ?? ""

        XCTAssertFalse(systemText.contains("[Memories]"), "Empty memories should not inject a block")
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

Expected: `BUILD FAILED` — `memoriesBlock(acceptedDir:)` and `memoriesContent` not yet present.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/MemoryInjectionTests.swift
git commit -m "Task 63a — MemoryInjectionTests (failing)"
```
