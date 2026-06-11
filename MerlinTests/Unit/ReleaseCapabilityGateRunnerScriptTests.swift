import XCTest

final class ReleaseCapabilityGateRunnerScriptTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var scriptURL: URL {
        repoRoot.appendingPathComponent("scripts/release/run-capability-gate.sh")
    }

    func testSelfCheckRequiresOwnedServicesConfigRestoreAndTimeouts() throws {
        let output = try runScript(["--self-test"])

        XCTAssertTrue(output.contains("self-test: owned llama.cpp router on 8081"))
        XCTAssertTrue(output.contains("self-test: owned xcalibre server on 8083"))
        XCTAssertTrue(output.contains("self-test: config backup and restore trap"))
        XCTAssertTrue(output.contains("self-test: bounded xcodebuild timeout"))
        XCTAssertTrue(output.contains("self-test: explicit release model IDs"))
        XCTAssertTrue(output.contains("self-test: fixture helper cleanup"))
        XCTAssertTrue(output.contains("self-test: pass"))
    }

    func testDryRunPinsTheExactReleaseScenarioInputs() throws {
        let output = try runScript(["--dry-run"])

        XCTAssertTrue(output.contains("qwen3-coder-local"))
        XCTAssertTrue(output.contains("qwen3-vl-local"))
        XCTAssertTrue(output.contains("127.0.0.1:8081"))
        XCTAssertTrue(output.contains("127.0.0.1:8083"))
        XCTAssertTrue(output.contains("MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle"))
        XCTAssertTrue(output.contains("MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle"))
        XCTAssertFalse(output.contains("qwen3-coder-next-local"))
    }

    func testScriptContainsCleanupForEveryOwnedPort() throws {
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("trap cleanup EXIT INT TERM"))
        XCTAssertTrue(script.contains("cleanup_port 8081"))
        XCTAssertTrue(script.contains("cleanup_port 8083"))
        XCTAssertTrue(script.contains("cleanup_fixture_helpers"))
        XCTAssertTrue(script.contains("TaskBoard.app/Contents/MacOS/TaskBoard"))
        XCTAssertTrue(script.contains("restore_user_config"))
    }

    func testTimeoutWatchdogCleanupKillsChildSleepTree() throws {
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("kill_tree \"$watchdog\""))
        XCTAssertFalse(script.contains("kill \"$watchdog\" 2>/dev/null || true"))
    }

    private func runScript(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path] + arguments
        process.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}
