import XCTest
@testable import Merlin

/// Task 299a — failing tests for git-hook wiring.
final class GitHookWiringTests: XCTestCase {

    private func makeTmpRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghw-\(UUID())", isDirectory: true)
        let hooks = dir.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        return dir
    }

    func testInstalledHooksReferenceAbsoluteBinaryPath() async throws {
        let repo = try makeTmpRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)

        let postCommit = try String(
            contentsOf: repo.appendingPathComponent(".git/hooks/post-commit"), encoding: .utf8)
        XCTAssertTrue(postCommit.contains(".merlin/bin/merlin-discipline"),
                      "the hook must call the absolute installed binary path")
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }
}
