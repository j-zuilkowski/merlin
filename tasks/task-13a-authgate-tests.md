# Phase 13a — AuthGate Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 12b complete: AuthMemory and PatternMatcher exist.

Note: `NullAuthPresenter` and `CapturingAuthPresenter` are defined in TestHelpers/NullAuthPresenter.swift
and are available to all three test targets. Do NOT redefine them in this file.

---

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
        _ = await gate.check(tool: "read_file", argument: "/tmp/x.txt")
        gate.reportFailure(tool: "read_file", argument: "/tmp/x.txt")
        // Pattern should have been rolled back
        XCTAssertFalse(memory.isAllowed(tool: "read_file", argument: "/tmp/NEW.txt"))
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `AuthGate` and `AuthDecision`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AuthGate` and `AuthDecision`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AuthGateTests.swift
git commit -m "Phase 13a — AuthGateTests (failing)"
```
