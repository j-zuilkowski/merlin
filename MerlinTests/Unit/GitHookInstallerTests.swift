import XCTest
@testable import Merlin

final class GitHookInstallerTests: XCTestCase {

    private func makeFakeGitRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrepo-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gitHooks = dir.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: gitHooks, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - install creates hook files

    func testInstallCreatesHookFiles() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        let postCommit = repo.appendingPathComponent(".git/hooks/post-commit")
        let prePush = repo.appendingPathComponent(".git/hooks/pre-push")
        XCTAssertTrue(FileManager.default.fileExists(atPath: postCommit.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prePush.path))
    }

    // MARK: - isInstalled after install

    func testIsInstalledAfterInstall() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - hook files are executable

    func testHooksAreExecutable() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        let postCommit = repo.appendingPathComponent(".git/hooks/post-commit").path
        let attrs = try FileManager.default.attributesOfItem(atPath: postCommit)
        if let perms = attrs[.posixPermissions] as? Int {
            XCTAssertTrue(perms & 0o111 != 0, "post-commit should be executable")
        }
    }

    // MARK: - uninstall removes hooks

    func testUninstallRemovesHooks() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        try await installer.uninstall(projectPath: repo.path)
        XCTAssertFalse(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - idempotent re-install

    func testReInstallIsIdempotent() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        try await installer.install(projectPath: repo.path) // second install
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - no .git directory throws notAGitRepo

    func testInstallWithoutGitThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nogit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = GitHookInstaller()
        do {
            try await installer.install(projectPath: dir.path)
            XCTFail("Expected notAGitRepo error")
        } catch GitHookInstaller.HookError.notAGitRepo {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - uninstall preserves foreign hooks

    func testUninstallPreservesForeignHook() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // Write a hook without the Merlin marker
        let foreignHook = repo.appendingPathComponent(".git/hooks/post-commit")
        try "#!/bin/sh\necho 'foreign hook'\n".write(
            to: foreignHook, atomically: true, encoding: .utf8)

        let installer = GitHookInstaller()
        try await installer.uninstall(projectPath: repo.path) // should not remove foreign hook
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignHook.path),
                      "Foreign hook should be preserved by uninstall")
    }
}
