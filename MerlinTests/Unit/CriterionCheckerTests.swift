import XCTest
@testable import Merlin

final class CriterionCheckerTests: XCTestCase {

    private actor ShellRunnerSpy: ShellRunning {
        var exitCode: Int
        var output: String
        private var _commands: [String] = []

        init(exitCode: Int = 0, output: String = "") {
            self.exitCode = exitCode
            self.output = output
        }

        func commands() -> [String] {
            _commands
        }

        func run(_ command: String) async -> (exitCode: Int, output: String) {
            _commands.append(command)
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
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertTrue(commands.isEmpty, "fileExists should not shell out")
    }

    func testShellExitZeroUsesShellRunnerCommand() async {
        let spy = ShellRunnerSpy(exitCode: 0)
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.shellExitZero(command: "swift --version"))
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertEqual(commands, ["swift --version"])
    }

    func testBuildSucceedsUsesXcodebuildInvocation() async {
        let spy = ShellRunnerSpy(exitCode: 0)
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.buildSucceeds)
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].contains("xcodebuild"))
    }

    func testTestsPassUsesXcodebuildTestInvocation() async {
        let spy = ShellRunnerSpy(exitCode: 0)
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.testsPass(scheme: "MerlinTests"))
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].contains("xcodebuild"))
        XCTAssertTrue(commands[0].contains("test"))
        XCTAssertTrue(commands[0].contains("MerlinTests"))
    }

    func testRegexMatchAgainstStdoutUsesShellOutput() async {
        let spy = ShellRunnerSpy(exitCode: 0, output: "hello from stdout")
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.regexMatch(pattern: "hello", in: .stdout))
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertFalse(commands.isEmpty)
    }

    func testRegexMatchAgainstFileUsesFileContent() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("criterion-checker-regex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("output.txt")
        try "needle in a haystack".write(to: fileURL, atomically: true, encoding: .utf8)

        let spy = ShellRunnerSpy(exitCode: 0, output: fileURL.path)
        let checker = CriterionChecker(shellRunner: spy)

        let result = await checker.check(.regexMatch(pattern: "needle", in: .file))
        let commands = await spy.commands()

        XCTAssertTrue(result)
        XCTAssertFalse(commands.isEmpty)
    }
}
