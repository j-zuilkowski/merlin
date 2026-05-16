import XCTest
@testable import Merlin

final class GitHookHardeningTests: XCTestCase {

    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // A minimal repo: just enough of a .git/hooks tree for the installer.
        let hooks = repoRoot
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
        try FileManager.default.createDirectory(
            at: hooks, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let repoRoot {
            try? FileManager.default.removeItem(at: repoRoot)
        }
    }

    private var hooksDir: URL {
        repoRoot.appendingPathComponent(".git").appendingPathComponent("hooks")
    }

    func testInstallOnCleanRepoSucceeds() async throws {
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repoRoot.path)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("pre-commit").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("post-commit").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("pre-push").path))
    }

    func testInstallThrowsOnForeignHook() async throws {
        // A pre-existing non-Merlin hook the user wrote themselves.
        try "#!/bin/sh\necho not merlin\n".write(
            to: hooksDir.appendingPathComponent("post-commit"),
            atomically: true, encoding: .utf8)

        let installer = GitHookInstaller()
        do {
            try await installer.install(projectPath: repoRoot.path)
            XCTFail("install() must refuse to clobber a foreign hook")
        } catch GitHookInstaller.HookError.foreignHookPresent(let path) {
            XCTAssertTrue(path.contains("post-commit"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testReinstallOverMerlinHookSucceeds() async throws {
        let installer = GitHookInstaller()
        // First install writes Merlin's marker-bearing hooks.
        try await installer.install(projectPath: repoRoot.path)
        // A second install over Merlin's own hooks must be allowed (idempotent).
        try await installer.install(projectPath: repoRoot.path)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("post-commit").path))
    }
}
