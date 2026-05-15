import XCTest
@testable import Merlin

final class AdapterRegistryTests: XCTestCase {

    // MARK: - register + adapter(for:) round-trip

    func testRegisterAndRetrieve() async throws {
        let registry = AdapterRegistry()
        let adapter = ProjectAdapter.makeStub(language: "kotlin")
        await registry.register(adapter, for: "kotlin")
        let retrieved = try await registry.adapter(for: "kotlin")
        XCTAssertEqual(retrieved.language, "kotlin")
    }

    func testNotFoundThrows() async {
        let registry = AdapterRegistry()
        do {
            _ = try await registry.adapter(for: "cobol")
            XCTFail("Expected notFound error")
        } catch AdapterRegistry.AdapterError.notFound(let lang) {
            XCTAssertEqual(lang, "cobol")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRegisterOverwrites() async throws {
        let registry = AdapterRegistry()
        let first = ProjectAdapter.makeStub(language: "swift", buildCommand: "xcodebuild-v1")
        let second = ProjectAdapter.makeStub(language: "swift", buildCommand: "xcodebuild-v2")
        await registry.register(first, for: "swift")
        await registry.register(second, for: "swift")
        let retrieved = try await registry.adapter(for: "swift")
        XCTAssertEqual(retrieved.buildCommand, "xcodebuild-v2")
    }

    // MARK: - loadFromDirectory

    func testLoadFromDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapters-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let toml = """
        language = "haskell"
        versioning_file = "cabal.project"
        versioning_field = "version"
        build_command = "cabal build"
        test_command = "cabal test"
        build_success_marker = "Build succeeded"
        build_failure_marker = "Build failed"
        """
        let file = dir.appendingPathComponent("haskell.toml")
        try toml.write(to: file, atomically: true, encoding: .utf8)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)
        let adapter = try await registry.adapter(for: "haskell")
        XCTAssertEqual(adapter.language, "haskell")
        XCTAssertEqual(adapter.buildCommand, "cabal build")
    }

    func testLoadFromDirectorySkipsNonToml() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapters-skip-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "not toml".write(
            to: dir.appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)
        // Should not throw; no adapters loaded, directory itself was fine
    }

    func testLoadFromMissingDirectoryThrows() async {
        let registry = AdapterRegistry()
        do {
            try await registry.loadFromDirectory("/nonexistent/adapters")
            XCTFail("Expected error")
        } catch {
            // Any error is acceptable — directory does not exist
        }
    }
}
