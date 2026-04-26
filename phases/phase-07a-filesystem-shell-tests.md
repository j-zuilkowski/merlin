# Phase 07a — FileSystem + Shell Tests

Context: HANDOFF.md. Write failing tests only.

## Write to: MerlinTests/Integration/FileSystemToolTests.swift

```swift
import XCTest
@testable import Merlin

final class FileSystemToolTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testWriteThenRead() async throws {
        let path = tmp.appendingPathComponent("test.txt").path
        try await FileSystemTools.writeFile(path: path, content: "hello")
        let result = try await FileSystemTools.readFile(path: path)
        XCTAssertTrue(result.contains("hello"))
        XCTAssertTrue(result.contains("1\t")) // has line numbers
    }

    func testListDirectory() async throws {
        let path = tmp.appendingPathComponent("file.txt").path
        try await FileSystemTools.writeFile(path: path, content: "x")
        let listing = try await FileSystemTools.listDirectory(path: tmp.path, recursive: false)
        XCTAssertTrue(listing.contains("file.txt"))
    }

    func testSearchFiles() async throws {
        let path = tmp.appendingPathComponent("match.swift").path
        try await FileSystemTools.writeFile(path: path, content: "let needle = 42")
        let result = try await FileSystemTools.searchFiles(pattern: "*.swift",
                                                           path: tmp.path,
                                                           contentPattern: "needle")
        XCTAssertTrue(result.contains("match.swift"))
    }

    func testDeleteFile() async throws {
        let path = tmp.appendingPathComponent("del.txt").path
        try await FileSystemTools.writeFile(path: path, content: "bye")
        try await FileSystemTools.deleteFile(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testMoveFile() async throws {
        let src = tmp.appendingPathComponent("a.txt").path
        let dst = tmp.appendingPathComponent("b.txt").path
        try await FileSystemTools.writeFile(path: src, content: "moved")
        try await FileSystemTools.moveFile(src: src, dst: dst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
    }
}
```

## Write to: MerlinTests/Integration/ShellToolTests.swift

```swift
final class ShellToolTests: XCTestCase {

    func testEchoCommand() async throws {
        let result = try await ShellTool.run(command: "echo hello", cwd: nil)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testFailingCommand() async throws {
        let result = try await ShellTool.run(command: "false", cwd: nil)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testWorkingDirectoryRespected() async throws {
        let result = try await ShellTool.run(command: "pwd", cwd: "/tmp")
        XCTAssertTrue(result.stdout.contains("tmp"))
    }

    func testStderrCaptured() async throws {
        let result = try await ShellTool.run(command: "ls /nonexistent 2>&1", cwd: nil)
        XCTAssertFalse(result.stderr.isEmpty || result.stdout.contains("No such"))
    }
}
```

## Acceptance
- [ ] Files compile (types missing — expected)
