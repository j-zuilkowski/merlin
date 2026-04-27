# Phase 36a — CLAUDEMDLoader Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 35b complete: inline diff commenting + submitDiffComments.

New surface introduced in phase 36b:
  - `CLAUDEMDLoader` — struct with static method:
    `load(projectPath: String) -> String`
    Searches upward from projectPath for CLAUDE.md and .merlin/CLAUDE.md, then ~/CLAUDE.md.
    Concatenates all found files (project-specific first, global last).
    Returns empty string if none found.
  - `AgenticEngine.claudeMDContent: String` — injected as a [Project instructions] block
    in the system prompt when non-empty

TDD coverage:
  File 1 — CLAUDEMDLoaderTests: returns empty when no files exist; finds file at project root;
            finds .merlin/CLAUDE.md; concatenates both; global ~/CLAUDE.md appended last;
            system prompt block wrapping

---

## Write to: MerlinTests/Unit/CLAUDEMDLoaderTests.swift

```swift
import XCTest
@testable import Merlin

final class CLAUDEMDLoaderTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-claudemd-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - No files

    func testReturnsEmptyWhenNoFilesExist() {
        let content = CLAUDEMDLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.isEmpty)
    }

    // MARK: - Project root CLAUDE.md

    func testFindsFileAtProjectRoot() throws {
        let fileURL = tmpDir.appendingPathComponent("CLAUDE.md")
        try "# Project instructions".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = CLAUDEMDLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.contains("Project instructions"))
    }

    // MARK: - .merlin/CLAUDE.md

    func testFindsDotMerlinSubdirectory() throws {
        let subdir = tmpDir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let fileURL = subdir.appendingPathComponent("CLAUDE.md")
        try "dotmerlin instructions".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = CLAUDEMDLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.contains("dotmerlin instructions"))
    }

    // MARK: - Concatenation order

    func testProjectRootAppearsBeforeDotMerlin() throws {
        let rootURL = tmpDir.appendingPathComponent("CLAUDE.md")
        try "ROOT".write(to: rootURL, atomically: true, encoding: .utf8)
        let subdir = tmpDir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "DOTMERLIN".write(to: subdir.appendingPathComponent("CLAUDE.md"),
                              atomically: true, encoding: .utf8)
        let content = CLAUDEMDLoader.load(projectPath: tmpDir.path, globalHome: nil)
        let rootIdx = content.range(of: "ROOT")!.lowerBound
        let dotIdx  = content.range(of: "DOTMERLIN")!.lowerBound
        XCTAssertLessThan(rootIdx, dotIdx, "Project root CLAUDE.md must appear before .merlin/CLAUDE.md")
    }

    func testGlobalHomeAppendedLast() throws {
        let rootURL = tmpDir.appendingPathComponent("CLAUDE.md")
        try "PROJECT".write(to: rootURL, atomically: true, encoding: .utf8)

        let globalDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("global-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: globalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: globalDir) }
        try "GLOBAL".write(to: globalDir.appendingPathComponent("CLAUDE.md"),
                           atomically: true, encoding: .utf8)

        let content = CLAUDEMDLoader.load(projectPath: tmpDir.path, globalHome: globalDir.path)
        let projIdx   = content.range(of: "PROJECT")!.lowerBound
        let globalIdx = content.range(of: "GLOBAL")!.lowerBound
        XCTAssertLessThan(projIdx, globalIdx, "Project instructions must appear before global CLAUDE.md")
    }

    // MARK: - System prompt wrapping

    func testSystemPromptBlockWrapsContent() throws {
        let fileURL = tmpDir.appendingPathComponent("CLAUDE.md")
        try "do the thing".write(to: fileURL, atomically: true, encoding: .utf8)
        let block = CLAUDEMDLoader.systemPromptBlock(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(block.contains("[Project instructions]") || block.contains("Project instructions"),
                      "Block must include a [Project instructions] header")
        XCTAssertTrue(block.contains("do the thing"))
    }

    func testSystemPromptBlockIsEmptyWhenNoFiles() {
        let block = CLAUDEMDLoader.systemPromptBlock(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(block.isEmpty)
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

Expected: `BUILD FAILED` with errors referencing `CLAUDEMDLoader`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/CLAUDEMDLoaderTests.swift
git commit -m "Phase 36a — CLAUDEMDLoaderTests (failing)"
```
