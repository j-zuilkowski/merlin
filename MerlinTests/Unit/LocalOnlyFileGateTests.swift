import XCTest
@testable import Merlin

final class LocalOnlyFileGateTests: XCTestCase {
    func testTrackedAPIKeysFileBlocksPrePush() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("{}", to: repo.appendingPathComponent("api-keys.json"))
        try runGit(repo, ["add", "-f", "api-keys.json"])

        let findings = LocalOnlyFileGate().check(projectPath: repo.path)

        XCTAssertEqual(findings.map(\.path), ["api-keys.json"])
    }

    func testTrackedNestedMerlinAPIKeysFileBlocksPrePush() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".merlin"),
            withIntermediateDirectories: true)
        try write("{}", to: repo.appendingPathComponent(".merlin/api-keys.json"))
        try runGit(repo, ["add", "-f", ".merlin/api-keys.json"])

        let findings = LocalOnlyFileGate().check(projectPath: repo.path)

        XCTAssertEqual(findings.map(\.path), [".merlin/api-keys.json"])
    }

    func testCleanTrackedFilesPass() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("# ok", to: repo.appendingPathComponent("README.md"))
        try runGit(repo, ["add", "README.md"])

        let findings = LocalOnlyFileGate().check(projectPath: repo.path)

        XCTAssertTrue(findings.isEmpty)
    }

    private func makeRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-only-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(repo, ["init"])
        return repo
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ repo: URL, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")) failed")
    }
}
