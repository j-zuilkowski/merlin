# Phase 48a — Hooks Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 47b complete: MemoryEngine in place.

New surface introduced in phase 48b:
  - `HookEngine` — actor; executes shell-script lifecycle hooks
  - `HookDecision` — enum: `.allow`, `.deny(reason: String)`
  - `HookEngine.runPreToolUse(toolName:input:) async -> HookDecision`
  - `HookEngine.runPostToolUse(toolName:result:) async -> String?` — returns modified result or nil
  - `HookEngine.runUserPromptSubmit(prompt:) async -> String?` — returns augmented prompt or nil
  - `HookEngine.runStop() async -> Bool` — returns true if stop should proceed
  - `HookEngine.configure(hooks: [HookConfig])` — loads hook definitions from AppSettings

Ordering rule: HookEngine.runPreToolUse fires BEFORE AuthGate. A hook that denies = fail-closed.
The user never sees an approval prompt for something a hook has already blocked.

Wire format:
  - Hook stdin: `{"tool": "<name>", "input": {...}}` for PreToolUse
  - Hook stdout: `{"decision": "allow"}` or `{"decision": "deny", "reason": "..."}`
  - Non-zero exit or JSON parse failure = deny (fail-closed)
  - PostToolUse stdout: modified result string (optional); empty stdout = pass through unchanged
  - UserPromptSubmit stdout: augmented prompt text (optional)
  - Stop stdout: `{"proceed": true}` or `{"proceed": false}`

TDD coverage:
  File 1 — HookEngineTests: allow decision, deny decision, fail-closed on crash, fail-closed on
           non-zero exit, PostToolUse passthrough, PostToolUse modification, UserPromptSubmit
           augmentation, Stop allow/deny, no hooks configured = allow, concurrent hook execution

---

## Write to: MerlinTests/Unit/HookEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class HookEngineTests: XCTestCase {

    // Each test uses a private HookEngine so hooks don't bleed between tests.
    private var engine: HookEngine!

    // MARK: - PreToolUse

    func test_preToolUse_noHooks_allows() async {
        engine = HookEngine(hooks: [])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .allow = decision { /* pass */ } else {
            XCTFail("Expected .allow, got \(decision)")
        }
    }

    func test_preToolUse_scriptReturnsAllow() async throws {
        let script = makeScript(stdout: #"{"decision":"allow"}"#, exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: ["cmd": "ls" as AnyObject])
        if case .allow = decision { /* pass */ } else {
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
        if case .deny = decision { /* pass */ } else {
            XCTFail("Expected .deny on non-zero exit, got \(decision)")
        }
    }

    func test_preToolUse_invalidJSON_failClosed() async throws {
        let script = makeScript(stdout: "not json", exitCode: 0)
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: script)])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny = decision { /* pass */ } else {
            XCTFail("Expected .deny on invalid JSON, got \(decision)")
        }
    }

    func test_preToolUse_scriptCrashes_failClosed() async throws {
        // /bin/false exits immediately with code 1
        engine = HookEngine(hooks: [HookConfig(event: "PreToolUse", command: "/bin/false")])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .deny = decision { /* pass */ } else {
            XCTFail("Expected .deny when script crashes, got \(decision)")
        }
    }

    func test_preToolUse_disabledHook_skipped() async throws {
        let script = makeScript(stdout: #"{"decision":"deny","reason":"should be skipped"}"#, exitCode: 0)
        var hook = HookConfig(event: "PreToolUse", command: script)
        hook.enabled = false
        engine = HookEngine(hooks: [hook])
        let decision = await engine.runPreToolUse(toolName: "bash", input: [:])
        if case .allow = decision { /* pass */ } else {
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
        if case .deny = decision { /* pass */ } else {
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
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                ofItemAtPath: tmp)
        return tmp
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `HookEngine`, `HookDecision` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/HookEngineTests.swift
git commit -m "Phase 48a — HookEngineTests (failing)"
```
