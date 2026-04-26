import XCTest
@testable import Merlin

@MainActor
final class AuthGateTests: XCTestCase {

    func testKnownAllowPatternPassesSilently() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let decision = await gate.check(tool: "read_file", argument: "/tmp/foo.txt")
        XCTAssertEqual(decision, .allow)
    }

    func testKnownDenyPatternBlocksSilently() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf /**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let decision = await gate.check(tool: "run_shell", argument: "rm -rf /")
        XCTAssertEqual(decision, .deny)
    }

    func testUnknownToolPromptsPresenter() async {
        let presenter = CapturingAuthPresenter(response: .allowOnce)
        let memory = AuthMemory(storePath: "/dev/null")
        let gate = AuthGate(memory: memory, presenter: presenter)
        let decision = await gate.check(tool: "write_file", argument: "/etc/hosts")
        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(presenter.wasPrompted)
    }

    func testAllowAlwaysWritesPattern() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
        let memory = AuthMemory(storePath: tmp)
        let presenter = CapturingAuthPresenter(response: .allowAlways(pattern: "/etc/**"))
        let gate = AuthGate(memory: memory, presenter: presenter)
        _ = await gate.check(tool: "write_file", argument: "/etc/hosts")
        XCTAssertTrue(memory.isAllowed(tool: "write_file", argument: "/etc/hosts"))
        try? FileManager.default.removeItem(atPath: tmp)
    }

    func testFailedCallNeverWritesPattern() async {
        let memory = AuthMemory(storePath: "/dev/null")
        let presenter = CapturingAuthPresenter(response: .allowAlways(pattern: "/tmp/**"))
        let gate = AuthGate(memory: memory, presenter: presenter)
        _ = await gate.check(tool: "read_file", argument: "/tmp/x.txt")
        gate.reportFailure(tool: "read_file", argument: "/tmp/x.txt")
        XCTAssertFalse(memory.isAllowed(tool: "read_file", argument: "/tmp/NEW.txt"))
    }
}
