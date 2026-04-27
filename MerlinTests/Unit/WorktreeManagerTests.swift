import XCTest
@testable import Merlin

final class WorktreeManagerTests: XCTestCase {

    private var manager: WorktreeManager!
    private var repoURL: URL!
    private var worktreeBase: URL!

    override func setUp() async throws {
        worktreeBase = URL(fileURLWithPath: "/tmp/wt-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeBase, withIntermediateDirectories: true)
        repoURL = worktreeBase.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        _ = try await shell("git init \(repoURL.path)")
        _ = try await shell("cd \(repoURL.path) && git commit --allow-empty -m 'init'")
        manager = WorktreeManager(worktreesBase: worktreeBase)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: worktreeBase)
    }

    func test_create_returnsURL() async throws {
        let id = UUID()
        let url = try await manager.create(sessionID: id, in: repoURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_create_pathMatchesSessionID() async throws {
        let id = UUID()
        let url = try await manager.create(sessionID: id, in: repoURL)
        XCTAssertTrue(url.path.contains(id.uuidString))
    }

    func test_create_alreadyExists_throws() async throws {
        let id = UUID()
        _ = try await manager.create(sessionID: id, in: repoURL)
        do {
            _ = try await manager.create(sessionID: id, in: repoURL)
            XCTFail("Expected alreadyExists error")
        } catch WorktreeError.alreadyExists {
            // pass
        }
    }

    func test_create_nonGitDir_throws() async throws {
        let plain = worktreeBase.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let id = UUID()
        do {
            _ = try await manager.create(sessionID: id, in: plain)
            XCTFail("Expected notAGitRepo error")
        } catch WorktreeError.notAGitRepo {
            // pass
        }
    }

    func test_remove_deletesWorktree() async throws {
        let id = UUID()
        let url = try await manager.create(sessionID: id, in: repoURL)
        try await manager.remove(sessionID: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_remove_notFound_throws() async throws {
        let id = UUID()
        do {
            try await manager.remove(sessionID: id)
            XCTFail("Expected notFound error")
        } catch WorktreeError.notFound {
            // pass
        }
    }

    func test_lock_setsLocked() async throws {
        let id = UUID()
        _ = try await manager.create(sessionID: id, in: repoURL)
        try await manager.lock(sessionID: id)
        let locked = await manager.isLocked(sessionID: id)
        XCTAssertTrue(locked)
    }

    func test_unlock_clearsLock() async throws {
        let id = UUID()
        _ = try await manager.create(sessionID: id, in: repoURL)
        try await manager.lock(sessionID: id)
        await manager.unlock(sessionID: id)
        let locked = await manager.isLocked(sessionID: id)
        XCTAssertFalse(locked)
    }

    func test_lockConflict_throws() async throws {
        let id = UUID()
        _ = try await manager.create(sessionID: id, in: repoURL)
        try await manager.lock(sessionID: id)
        do {
            try await manager.lock(sessionID: id)
            XCTFail("Expected lockConflict error")
        } catch WorktreeError.lockConflict {
            // pass
        }
    }

    func test_isLocked_falseByDefault() async throws {
        let id = UUID()
        _ = try await manager.create(sessionID: id, in: repoURL)
        let locked = await manager.isLocked(sessionID: id)
        XCTAssertFalse(locked)
    }

    func test_path_returnsURLAfterCreate() async throws {
        let id = UUID()
        let created = try await manager.create(sessionID: id, in: repoURL)
        let retrieved = await manager.path(for: id)
        XCTAssertEqual(retrieved, created)
    }

    func test_path_returnsNilForUnknown() async {
        let path = await manager.path(for: UUID())
        XCTAssertNil(path)
    }

    private func shell(_ cmd: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    cont.resume(throwing: URLError(.unknown))
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
