import XCTest
@testable import Merlin

final class HookEngineTests: XCTestCase {
    private var engine: HookEngine!

    // MARK: - PreToolUse

    func test_preToolUse_noHooks_allows() async {
        engine = HookEngine(hooks: [])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .allow = decision {
        } else {
            XCTFail("Expected .allow, got \(decision)")
        }
    }

    func test_preToolUse_scriptReturnsAllow() async throws {
        let script = makeScript(stdout: #"{"decision":"allow"}"#, exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: ["cmd": "ls"])
        if case .allow = decision {
        } else {
            XCTFail("Expected .allow, got \(decision)")
        }
    }

    func test_preToolUse_scriptReturnsDeny() async throws {
        let script = makeScript(stdout: #"{"decision":"deny","reason":"blocked by policy"}"#, exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny(let reason) = decision {
            XCTAssertEqual(reason, "blocked by policy")
        } else {
            XCTFail("Expected .deny, got \(decision)")
        }
    }

    func test_preToolUse_nonZeroExit_failClosed() async throws {
        let script = makeScript(stdout: "", exitCode: 1)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny = decision {
        } else {
            XCTFail("Expected .deny on non-zero exit, got \(decision)")
        }
    }

    func test_preToolUse_invalidJSON_failClosed() async throws {
        let script = makeScript(stdout: "not json", exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny = decision {
        } else {
            XCTFail("Expected .deny on invalid JSON, got \(decision)")
        }
    }

    func test_preToolUse_scriptCrashes_failClosed() async throws {
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: "/bin/false")])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny = decision {
        } else {
            XCTFail("Expected .deny when script crashes, got \(decision)")
        }
    }

    func test_preToolUse_disabledHook_skipped() async throws {
        let script = makeScript(stdout: #"{"decision":"deny","reason":"should be skipped"}"#, exitCode: 0)
        var hook = HookConfig(event: "PreToolUse", command: script)
        hook.enabled = false
        engine = HookEngine(hooks: [hook])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .allow = decision {
        } else {
            XCTFail("Disabled hook should be skipped")
        }
    }

    // MARK: - PostToolUse

    func test_postToolUse_noHooks_returnsNil() async {
        engine = HookEngine(hooks: [])
        let modified = await engine.runPostToolUse(toolName: "bash", result: "original")
        XCTAssertNil(modified)
    }

    func test_postToolUse_emptyStdout_returnsNil() async throws {
        let script = makeScript(stdout: "", exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PostToolUse", command: script)])
        let modified = await engine.runPostToolUse(toolName: "bash", result: "original")
        XCTAssertNil(modified)
    }

    func test_postToolUse_scriptOutputModifiesResult() async throws {
        let script = makeScript(stdout: "modified result", exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PostToolUse", command: script)])
        let modified = await engine.runPostToolUse(toolName: "bash", result: "original")
        XCTAssertEqual(modified, "modified result")
    }

    // MARK: - UserPromptSubmit

    func test_userPromptSubmit_noHooks_returnsNil() async {
        engine = HookEngine(hooks: [])
        let augmented = await engine.runUserPromptSubmit(prompt: "hello")
        XCTAssertNil(augmented)
    }

    func test_userPromptSubmit_scriptAugmentsPrompt() async throws {
        let script = makeScript(stdout: "hello augmented", exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "UserPromptSubmit", command: script)])
        let augmented = await engine.runUserPromptSubmit(prompt: "hello")
        XCTAssertEqual(augmented, "hello augmented")
    }

    // MARK: - Stop

    func test_stop_noHooks_returnsTrue() async {
        engine = HookEngine(hooks: [])
        let proceed = await engine.runStop()
        XCTAssertTrue(proceed)
    }

    func test_stop_scriptAllows() async throws {
        let script = makeScript(stdout: #"{"proceed":true}"#, exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "Stop", command: script)])
        let proceed = await engine.runStop()
        XCTAssertTrue(proceed)
    }

    func test_stop_scriptDenies() async throws {
        let script = makeScript(stdout: #"{"proceed":false}"#, exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "Stop", command: script)])
        let proceed = await engine.runStop()
        XCTAssertFalse(proceed)
    }

    // MARK: - configure

    func test_configure_replacesHooks() async throws {
        engine = HookEngine(hooks: [])
        let denyScript = makeScript(stdout: #"{"decision":"deny","reason":"reconfigured"}"#, exitCode: 0)
        await engine.configure(hooks: [HookConfig(event: "PreToolUse", command: denyScript)])
        let decision = await engine.runPreToolUse(toolName: "any", input: [:])
        if case .deny = decision {
        } else {
            XCTFail("Expected .deny after configure, got \(decision)")
        }
    }

    // MARK: - Helpers

    private func makeScript(stdout: String, exitCode: Int) -> String {
        let tmp = "/tmp/hook-\(UUID().uuidString).sh"
        let body = """
        #!/bin/sh
        echo '\(stdout.replacingOccurrences(of: "'", with: "'\\''"))'
        exit \(exitCode)
        """
        try? body.write(toFile: tmp, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp)
        return tmp
    }
}
