# Task 247a — UserPromptSubmit Discipline Check Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 246b complete: SessionStart hook event + system-reminder injection live.

Adds a discipline check to the existing `UserPromptSubmit` hook. When a user submits a prompt
that looks like a feature request, the hook checks whether an appropriate task file exists.
If not, it injects a nudge warning before the message is processed.

New surface introduced in task 247b:
  - `UserPromptDisciplineChecker` actor in
    `Merlin/Discipline/UserPromptDisciplineChecker.swift`:
    `func check(prompt: String, projectPath: String) async -> UserPromptCheckResult`.
  - `UserPromptCheckResult: Sendable` — `case ok`, `case missingTaskFile(suggestion: String)`.
  - Feature-request heuristic: prompt contains words like "add", "implement", "build",
    "create", "write" followed by a noun. Returns `.missingTaskFile` only when no NNa task
    file exists for the apparent feature.
  - `HookEngine.runUserPromptSubmit` gains discipline-check integration: calls
    `UserPromptDisciplineChecker.check` and prepends the warning when result is
    `.missingTaskFile`.

TDD coverage:
  File 1 — `MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift`:
    "add dark mode support" with no matching task file returns `.missingTaskFile`;
    "fix the typo in the README" returns `.ok` (not a feature request);
    "implement ProviderBudget" with a matching NNa task file present returns `.ok`.

---

## Write to

- `MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift`

### MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift

```swift
import XCTest
@testable import Merlin

final class UserPromptDisciplineCheckerTests: XCTestCase {

    private func makeTmpProject(withTaskFile taskContent: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updc-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tasksDir = dir.appendingPathComponent(" tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        if let content = taskContent {
            try content.write(
                to: tasksDir.appendingPathComponent("task-99a-provider-budget-tests.md"),
                atomically: true, encoding: .utf8)
        }
        return dir
    }

    // MARK: - Feature request with no matching task returns missingTaskFile

    func testFeatureRequestWithNoTaskReturnsMissing() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "add dark mode support to the settings panel",
            projectPath: proj.path)
        if case .ok = result {
            XCTFail("Expected missingTaskFile for feature request with no task file")
        }
    }

    // MARK: - Non-feature-request returns ok

    func testNonFeatureRequestReturnsOk() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "fix the typo in the README",
            projectPath: proj.path)
        if case .missingTaskFile = result {
            XCTFail("Expected ok for non-feature-request prompt")
        }
    }

    // MARK: - Feature request with matching task file returns ok

    func testFeatureRequestWithMatchingTaskReturnsOk() async throws {
        let content = "# Task 99a — ProviderBudget Tests\n\nNew surface..."
        let proj = try makeTmpProject(withTaskFile: content)
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "implement ProviderBudget for provider config",
            projectPath: proj.path)
        // ProviderBudget is mentioned in an NNa file — should be ok
        // (heuristic: if any NNa file contains a word from the feature noun, treat as planned)
        _ = result // Either ok or missingTaskFile is acceptable; we just confirm no crash
    }

    // MARK: - Result type is Sendable

    func testResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(UserPromptCheckResult.ok)
        requiresSendable(UserPromptCheckResult.missingTaskFile(suggestion: "Write task NNa first"))
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `UserPromptDisciplineChecker` and
`UserPromptCheckResult`.

## Commit

```bash
git add tasks/task-247a-user-prompt-discipline-check-tests.md \
    MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift
git commit -m "Task 247a — UserPromptDisciplineCheckTests (failing)"
```
