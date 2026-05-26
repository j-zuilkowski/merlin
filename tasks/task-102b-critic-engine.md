# Task 102b — CriticEngine (Stage 1 + Stage 2, graceful degradation)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 102a complete: failing CriticEngine tests in place.

---

## Write to: Merlin/Engine/CriticEngine.swift

```swift
import Foundation

// MARK: - CriticResult

enum CriticResult: Equatable, Sendable {
    case pass
    case fail(reason: String)
    case skipped   // both stages unavailable — caller shows "unverified" badge
}

// MARK: - ShellRunning

/// Protocol for running shell commands — testable without ShellTool dependency.
protocol ShellRunning: Sendable {
    func run(_ command: String) async -> (exitCode: Int, output: String)
}

struct LiveShellRunner: ShellRunning {
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (Int(process.terminationStatus), output))
                } catch {
                    continuation.resume(returning: (1, error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - CriticEngine

/// Two-stage critic:
///   Stage 1 — deterministic domain verification (VerificationBackend → ShellTool)
///   Stage 2 — reason-slot model evaluation (graceful degradation if unavailable)
///
/// Stage 1 always runs when the backend provides commands.
/// Stage 2 runs only when the reason provider is configured.
/// If both stages are unavailable, result is `.skipped` — caller shows "unverified" badge.
actor CriticEngine {

    private let verificationBackend: any VerificationBackend
    private let reasonProvider: (any LLMProvider)?
    private let shellRunner: any ShellRunning

    init(
        verificationBackend: any VerificationBackend,
        reasonProvider: (any LLMProvider)?,
        shellRunner: any ShellRunning = LiveShellRunner()
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = reasonProvider
        self.shellRunner = shellRunner
    }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {

        // Stage 1 — domain verification
        let stage1Result = await runStage1(taskType: taskType)

        switch stage1Result {
        case .fail(let reason):
            return .fail(reason: reason)
        case .pass:
            // Stage 1 passed — run Stage 2 if available
            return await runStage2(output: output, context: context, taskType: taskType)
                ?? .pass
        case .skipped:
            // No Stage 1 commands — try Stage 2
            return await runStage2(output: output, context: context, taskType: taskType)
                ?? .skipped
        }
    }

    // MARK: - Stage 1

    private func runStage1(taskType: DomainTaskType) async -> CriticResult {
        guard let commands = verificationBackend.verificationCommands(for: taskType),
              !commands.isEmpty
        else {
            return .skipped
        }

        for cmd in commands {
            let (exitCode, output) = await shellRunner.run(cmd.command)
            let passed: Bool
            switch cmd.passCondition {
            case .exitCode(let expected):
                passed = exitCode == expected
            case .outputContains(let substring):
                passed = output.contains(substring)
            case .custom(let predicate):
                passed = predicate(output)
            }
            if !passed {
                return .fail(reason: "\(cmd.label) failed\(output.isEmpty ? "" : ": \(output.prefix(200))")")
            }
        }
        return .pass
    }

    // MARK: - Stage 2

    /// Returns nil if reason provider is unavailable (graceful degradation).
    private func runStage2(
        output: String,
        context: [Message],
        taskType: DomainTaskType
    ) async -> CriticResult? {
        guard let provider = reasonProvider else { return nil }

        let prompt = """
        You are a critic reviewing AI-generated output for a \(taskType.displayName) task.
        Review the following output and respond with exactly one of:
          PASS: <brief reason>
          FAIL: <specific issue>

        Output to review:
        \(output.prefix(4000))
        """

        let request = CompletionRequest(
            model: provider.id,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )

        do {
            var fullResponse = ""
            let stream = try await provider.complete(request: request)
            for try await chunk in stream {
                fullResponse += chunk.delta?.content ?? ""
            }

            let trimmed = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("PASS") {
                return .pass
            } else if trimmed.hasPrefix("FAIL") {
                let reason = trimmed.dropFirst(5).trimmingCharacters(in: .init(charactersIn: ": "))
                return .fail(reason: String(reason))
            } else {
                // Ambiguous response — treat as pass (don't block on critic uncertainty)
                return .pass
            }
        } catch {
            // Stage 2 provider error → graceful degradation (same as unavailable)
            return nil
        }
    }
}
```

---

## Wire CriticEngine into AgenticEngine

Add a `criticEngine` property to `AgenticEngine`:

```swift
// In AgenticEngine — add property:
private var criticEngine: CriticEngine {
    CriticEngine(
        verificationBackend: (try? await DomainRegistry.shared.activeDomain())
            .verificationBackend ?? NullVerificationBackend(),
        reasonProvider: provider(for: .reason)
    )
}
```

Note: The critic is not yet wired into `runLoop()` — that happens in Task 103 (planner + complexity routing). This task only establishes the `CriticEngine` actor and its two-stage logic.

---

## project.yml additions

Add:
```yaml
- Merlin/Engine/CriticEngine.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'CriticEngine.*passed|CriticEngine.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; CriticEngineTests → 5 pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/CriticEngine.swift \
        Merlin/Engine/AgenticEngine.swift \
        project.yml
git commit -m "Task 102b — CriticEngine (Stage 1 domain verification + Stage 2 reason slot, graceful degradation)"
```

## Fixes

### LiveShellRunner pipe deadlock + verification timeout (2026-05-19)

LiveShellRunner ran the subprocess with `try process.run(); process.waitUntilExit(); … readDataToEndOfFile()` — two bugs in eight lines:

- **Pipe deadlock.** Reading after wait means a child producing more than the 64KB pipe buffer (anything xcodebuild test or cargo test emits) blocks writing, while the parent blocks waiting for it to exit. The pair deadlocks the moment buffer fills. S1's critic hung the entire 21-minute window between `critic.evaluate.start` and the 1800s test timeout this way.
- **No timeout.** Even with the pipe deadlock fixed, a wedged child — e.g. an xcodebuild test that deadlocked against a stale `SWBBuildService` or zombie test runners from prior runs — would still hang the critic forever. The critic has no business waiting unbounded on a verification subprocess.

Fix: drain the pipe on a background `DispatchQueue` and wait with a `DispatchSemaphore` deadline (`Self.timeoutSeconds = 300`). On timeout SIGKILL the process and return exit code 124 with a `LiveShellRunner timeout after …s: <command>` message. The blocking work moved out of `Task.detached` into a sync `DispatchQueue.global().async` block — `DispatchSemaphore.wait` is forbidden in async contexts under strict concurrency.

This unblocks the critic's correction → criticExhausted → designated-provider escalation rung (see `EscalationHandler.swift` Fixes): a verification subprocess that wedges now fails fast, the critic returns `.fail`, retries run, and on exhaustion the escalation routes to the stronger provider — instead of the loop dying in a silent xcodebuild deadlock.
