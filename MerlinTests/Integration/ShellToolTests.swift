import XCTest
@testable import Merlin

final class ShellToolTests: XCTestCase {

    func testEchoCommand() async throws {
        let result = try await ShellTool.run(command: "echo hello", cwd: nil)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testFailingCommand() async throws {
        let result = try await ShellTool.run(command: "false", cwd: nil)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testWorkingDirectoryRespected() async throws {
        let result = try await ShellTool.run(command: "pwd", cwd: "/tmp")
        XCTAssertTrue(result.stdout.contains("tmp"))
    }

    func testStderrCaptured() async throws {
        let result = try await ShellTool.run(command: "ls /nonexistent 2>&1", cwd: nil)
        XCTAssertFalse(result.stderr.isEmpty || result.stdout.contains("No such"))
    }
}
