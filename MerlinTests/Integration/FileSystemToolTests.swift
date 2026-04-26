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
