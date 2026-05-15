import XCTest
@testable import Merlin

final class AdapterSeedTests: XCTestCase {

    func testInstallSeedAdaptersWritesFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let swiftFile = dir.appendingPathComponent("swift-xcode.toml")
        let rustFile  = dir.appendingPathComponent("rust-cargo.toml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftFile.path),
                      "swift-xcode.toml not found")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rustFile.path),
                      "rust-cargo.toml not found")
    }

    func testSeedAdaptersLoadCorrectLanguages() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-load-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        let swift = try await registry.adapter(for: "swift")
        XCTAssertEqual(swift.language, "swift")
        XCTAssertEqual(swift.versioningFile, "project.yml")
        XCTAssertFalse(swift.whyCommentTriggers.isEmpty,
                       "Swift adapter should have WHY triggers")

        let rust = try await registry.adapter(for: "rust")
        XCTAssertEqual(rust.language, "rust")
        XCTAssertEqual(rust.versioningFile, "Cargo.toml")
        XCTAssertFalse(rust.whyCommentTriggers.isEmpty,
                       "Rust adapter should have WHY triggers")
    }

    func testSeedAdaptersHaveManualCoveragePatterns() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-patterns-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        let swift = try await registry.adapter(for: "swift")
        XCTAssertFalse(swift.manualCoveragePatterns.isEmpty,
                       "Swift adapter should have manual coverage patterns")
    }
}
