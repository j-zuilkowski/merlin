import XCTest
@testable import Merlin

final class CriterionCheckerTests: XCTestCase {

    private final class ShellRunnerSpy: @unchecked Sendable, ShellRunning {
        private let lock = NSLock()
        private var _commands: [String] = []
        var exitCode: Int = 0
        var output: String = ""

        var commands: [String] {
            lock.lock()
            defer { lock.unlock() }
            return _commands
        }

        func run(_ command: String) async -> (exitCode: Int, output: String) {
            lock.lock()
            _commands.append(command)
            lock.unlock()
            return (exitCode, output)
        }
    }

    func testProseCriterionAlwaysReturnsFalse() async {
        let checker = CriterionChecker(shellRunner: ShellRunnerSpy())

        let result = await checker.check(.prose("explain the result"))

        XCTAssertFalse(result)
    }

    func testFileExistsUsesFileManagerWithoutShellingOut() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("criterion-checker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("artifact.txt")
        try "ok".write(to: fileURL, atomically: true, encoding: .utf8)

        let spy = ShellRunnerSpy()
        let checker = CriterionChecker(shellRunner: spy)
        let result = await checker.check(.fileExists(path: fileURL.path))

        XCTAssertTrue(result)
        XCTAssertTrue(spy.commands.isEmpty, "fileExists should not shell out")
    }

    func testShellExitZeroUsesShellRunnerCommand() async {
        let spy = ShellRunnerSpy()
        spy.exitCode = 0
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.shellExitZero(command: "swift --version"))

        XCTAssertTrue(result)
        XCTAssertEqual(spy.commands, ["swift --version"])
    }

    func testBuildSucceedsUsesXcodebuildInvocation() async {
        let spy = ShellRunnerSpy()
        spy.exitCode = 0
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.buildSucceeds)

        XCTAssertTrue(result)
        XCTAssertEqual(spy.commands.count, 1)
        XCTAssertTrue(spy.commands[0].contains("xcodebuild"))
    }

    func testTestsPassUsesXcodebuildTestInvocation() async {
        let spy = ShellRunnerSpy()
        spy.exitCode = 0
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.testsPass(scheme: "MerlinTests"))

        XCTAssertTrue(result)
        XCTAssertEqual(spy.commands.count, 1)
        XCTAssertTrue(spy.commands[0].contains("xcodebuild"))
        XCTAssertTrue(spy.commands[0].contains("test"))
        XCTAssertTrue(spy.commands[0].contains("MerlinTests"))
    }

    func testRegexMatchAgainstStdoutUsesShellOutput() async {
        let spy = ShellRunnerSpy()
        spy.exitCode = 0
        spy.output = "hello from stdout"
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.regexMatch(pattern: "hello", in: .stdout))

        XCTAssertTrue(result)
        XCTAssertFalse(spy.commands.isEmpty)
    }

    func testRegexMatchAgainstFileUsesFileContent() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("criterion-checker-regex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("output.txt")
        try "needle in a haystack".write(to: fileURL, atomically: true, encoding: .utf8)

        let spy = ShellRunnerSpy()
        spy.exitCode = 0
        spy.output = fileURL.path
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.regexMatch(pattern: "needle", in: .file))

        XCTAssertTrue(result)
        XCTAssertFalse(spy.commands.isEmpty)
    }
}
