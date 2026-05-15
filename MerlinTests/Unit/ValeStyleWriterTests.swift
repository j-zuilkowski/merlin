import XCTest
@testable import Merlin

final class ValeStyleWriterTests: XCTestCase {

    func testWriteStylesCreatesFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vale-styles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: dir.path)

        let merlinDir = dir.appendingPathComponent("Merlin")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: merlinDir.appendingPathComponent("readability.yml").path),
            "readability.yml should exist")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: merlinDir.appendingPathComponent("accept.txt").path),
            "accept.txt should exist")
    }

    func testWriteStylesIsIdempotent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vale-idem-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: dir.path)
        try await writer.writeStyles(to: dir.path)
    }
}
