import XCTest
@testable import Merlin

/// Phase 308a — failing tests for StubMarkerScanner.
final class StubMarkerScannerTests: XCTestCase {

    private func makeTmpProject(file: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubscan-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent(file),
                          atomically: true, encoding: .utf8)
        return dir
    }

    func testHardStubsAndDeferralMarkersAreFound() async throws {
        let proj = try makeTmpProject(file: "Source.swift", content: """
        import Foundation
        func unfinished() {
            fatalError("wire this up")
        }
        // TODO: implement caching
        let ready = true
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains { $0.marker == "fatalError" && $0.isHardStub },
                      "fatalError must be flagged as a hard stub")
        XCTAssertTrue(findings.contains { $0.marker == "TODO" && !$0.isHardStub },
                      "a TODO comment must be flagged as a deferral marker")
    }

    func testTestDirectoriesAreSkipped() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubscan-\(UUID())", isDirectory: true)
        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(
            at: testsDir, withIntermediateDirectories: true)
        try "// TODO: not a production stub\nlet x = 1\n"
            .write(to: testsDir.appendingPathComponent("FooTests.swift"),
                   atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let findings = await StubMarkerScanner().scan(projectPath: dir.path)
        XCTAssertTrue(findings.isEmpty, "markers under Tests/ must be skipped")
    }
}
