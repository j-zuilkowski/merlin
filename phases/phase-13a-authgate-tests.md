# Phase 13a — AuthGate Tests

Context: HANDOFF.md. AuthMemory + PatternMatcher exist. Write failing tests only.

## Write to: MerlinTests/Unit/AuthGateTests.swift

```swift
import XCTest
@testable import Merlin

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
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf *")
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
        // Simulate a failed execution — gate should not persist on failure
        _ = await gate.check(tool: "read_file", argument: "/tmp/x.txt")
        gate.reportFailure(tool: "read_file", argument: "/tmp/x.txt")
        // Pattern should have been rolled back
        XCTAssertFalse(memory.isAllowed(tool: "read_file", argument: "/tmp/NEW.txt"))
    }
}

// Test doubles
final class NullAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        .deny  // Never called in these tests
    }
}

final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false
    init(response: AuthDecision) { self.response = response }
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true
        return response
    }
}
```

## Acceptance
- [ ] Compiles (types missing — expected)
