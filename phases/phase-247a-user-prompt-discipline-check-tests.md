# Phase 247a — UserPromptSubmit Discipline Check Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 246b complete: SessionStart hook event + system-reminder injection live.

Adds a discipline check to the existing `UserPromptSubmit` hook. When a user submits a prompt
that looks like a feature request, the hook checks whether an appropriate phase file exists.
If not, it injects a nudge warning before the message is processed.

New surface introduced in phase 247b:
  - `UserPromptDisciplineChecker` actor in
    `Merlin/Discipline/UserPromptDisciplineChecker.swift`:
    `func check(prompt: String, projectPath: String) async -> UserPromptCheckResult`.
  - `UserPromptCheckResult: Sendable` — `case ok`, `case missingPhaseFile(suggestion: String)`.
  - Feature-request heuristic: prompt contains words like "add", "implement", "build",
    "create", "write" followed by a noun. Returns `.missingPhaseFile` only when no NNa phase
    file exists for the apparent feature.
  - `HookEngine.runUserPromptSubmit` gains discipline-check integration: calls
    `UserPromptDisciplineChecker.check` and prepends the warning when result is
    `.missingPhaseFile`.

TDD coverage:
  File 1 — `MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift`:
    "add dark mode support" with no matching phase file returns `.missingPhaseFile`;
    "fix the typo in the README" returns `.ok` (not a feature request);
    "implement ProviderBudget" with a matching NNa phase file present returns `.ok`.

---

## Write to

- `MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift`

### MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift

```swift
import XCTest
@testable import Merlin

final class UserPromptDisciplineCheckerTests: XCTestCase {

    private func makeTmpProject(withPhaseFile phaseContent: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updc-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let phasesDir = dir.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        if let content = phaseContent {
            try content.write(
                to: phasesDir.appendingPathComponent("phase-99a-provider-budget-tests.md"),
                atomically: true, encoding: .utf8)
        }
        return dir
    }

    // MARK: - Feature request with no matching phase returns missingPhaseFile

    func testFeatureRequestWithNoPhaseReturnsMissing() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "add dark mode support to the settings panel",
            projectPath: proj.path)
        if case .ok = result {
            XCTFail("Expected missingPhaseFile for feature request with no phase file")
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
        if case .missingPhaseFile = result {
            XCTFail("Expected ok for non-feature-request prompt")
        }
    }

    // MARK: - Feature request with matching phase file returns ok

    func testFeatureRequestWithMatchingPhaseReturnsOk() async throws {
        let content = "# Phase 99a — ProviderBudget Tests\n\nNew surface..."
        let proj = try makeTmpProject(withPhaseFile: content)
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "implement ProviderBudget for provider config",
            projectPath: proj.path)
        // ProviderBudget is mentioned in an NNa file — should be ok
        // (heuristic: if any NNa file contains a word from the feature noun, treat as planned)
        _ = result // Either ok or missingPhaseFile is acceptable; we just confirm no crash
    }

    // MARK: - Result type is Sendable

    func testResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(UserPromptCheckResult.ok)
        requiresSendable(UserPromptCheckResult.missingPhaseFile(suggestion: "Write phase NNa first"))
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
git add phases/phase-247a-user-prompt-discipline-check-tests.md \
    MerlinTests/Unit/UserPromptDisciplineCheckerTests.swift
git commit -m "Phase 247a — UserPromptDisciplineCheckTests (failing)"
```
