# Task 243a — TaskScanner Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 242b complete: ProjectConfig + ProjectConfigLoader live.

Introduces `TaskScanner`, the load-bearing v2.2 component that validates task files stay in
sync with the codebase. Builds a drift report classified into four colours.

New surface introduced in task 243b:
  - `DriftSeverity: Sendable` enum — `case green, yellow, red, orange`.
  - `DriftFinding: Sendable, Identifiable` — `id: UUID`, `taskID: String?`, `surface: String`,
    `severity: DriftSeverity`, `evidence: String`, `suggestedAction: String`.
  - `actor TaskScanner` — `func scan(projectPath: String) async -> [DriftFinding]`.
  - TaskScanner reads `tasks/` directory, extracts "New surface introduced in task NNb:"
    blocks from each NNb file, greps for each named symbol against the source tree:
    - green: symbol found, shape matches declaration.
    - yellow: symbol found but signature differs from declaration.
    - red: symbol absent from code (deleted without addendum).
    - orange: public symbol in code not declared in any task file.

TDD coverage:
  File 1 — `MerlinTests/Unit/DriftSeverityTests.swift`: enum cases exist; `DriftFinding`
    conforms to `Identifiable` with UUID `id`; `DriftFinding` is `Sendable`.
  File 2 — `MerlinTests/Unit/TaskScannerTests.swift`: scan of a tmp project with a task NNb
    that declares "func fooBar()" but no such symbol in source returns a `.red` finding;
    a source file containing `func fooBar()` with a matching NNb declaration returns `.green`;
    a source file with an undeclared public symbol returns `.orange`; scanner handles empty
    tasks/ directory without crashing.

---

## Write to

- `MerlinTests/Unit/DriftSeverityTests.swift`
- `MerlinTests/Unit/TaskScannerTests.swift`

### MerlinTests/Unit/DriftSeverityTests.swift

```swift
import XCTest
@testable import Merlin

final class DriftSeverityTests: XCTestCase {

    func testAllCasesExist() {
        let cases: [DriftSeverity] = [.green, .yellow, .red, .orange]
        XCTAssertEqual(cases.count, 4)
    }

    func testDriftFindingIdentifiable() {
        let f = DriftFinding(
            id: UUID(),
            taskID: "233b",
            surface: "ProviderBudget",
            severity: .red,
            evidence: "No match in source tree",
            suggestedAction: "Restore or write addendum"
        )
        // id must be the stable identifier
        XCTAssertNotNil(f.id)
    }

    func testDriftFindingIsSendable() {
        // Compile-time check: DriftFinding is Sendable
        func requiresSendable<T: Sendable>(_ value: T) {}
        let f = DriftFinding(
            id: UUID(),
            taskID: nil,
            surface: "AgenticEngine",
            severity: .green,
            evidence: "Found at AgenticEngine.swift:12",
            suggestedAction: "No action needed"
        )
        requiresSendable(f)
    }
}
```

### MerlinTests/Unit/TaskScannerTests.swift

```swift
import XCTest
@testable import Merlin

final class TaskScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanproj-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tasksDir = dir.appendingPathComponent(" tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTaskNNb(_ dir: URL, taskID: String, surface: String) throws {
        let content = """
        # Task \(taskID) — Test Task

        ## Context
        Test task file.

        New surface introduced in task \(taskID):
          - `\(surface)` — test surface

        ---
        """
        let tasksDir = dir.appendingPathComponent(" tasks")
        try content.write(
            to: tasksDir.appendingPathComponent("task-\(taskID)-test.md"),
            atomically: true, encoding: .utf8)
    }

    private func writeSwiftSource(_ dir: URL, name: String, content: String) throws {
        let srcDir = dir.appendingPathComponent("Src")
        try content.write(
            to: srcDir.appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    // MARK: - red: symbol absent from code

    func testRedFindingWhenSymbolAbsent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeTaskNNb(proj, taskID: "99b", surface: "func fooBar()")
        // No matching source file

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let reds = findings.filter { $0.severity == .red }
        XCTAssertFalse(reds.isEmpty, "Expected at least one red finding for missing fooBar")
    }

    // MARK: - green: symbol present and declared

    func testGreenWhenSymbolPresent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeTaskNNb(proj, taskID: "99b", surface: "func fooBar()")
        try writeSwiftSource(proj, name: "FooBar", content: """
        import Foundation
        func fooBar() { }
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let greens = findings.filter { $0.severity == .green && $0.surface.contains("fooBar") }
        XCTAssertFalse(greens.isEmpty, "Expected green finding for present fooBar")
        let reds = findings.filter { $0.severity == .red && $0.surface.contains("fooBar") }
        XCTAssertTrue(reds.isEmpty, "Should not be red when symbol is present")
    }

    // MARK: - orange: public symbol not declared in any task

    func testOrangeWhenUndeclaredPublicSymbol() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // No task file declares "func undeclaredPublic()"
        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let oranges = findings.filter { $0.severity == .orange }
        XCTAssertFalse(oranges.isEmpty,
            "Expected orange finding for undeclared public symbol")
    }

    // MARK: - empty  tasks directory

    func testEmptyTasksDirDoesNotCrash() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = TaskScanner()
        // Should return without crashing
        let findings = await scanner.scan(projectPath: proj.path)
        // Orange findings for source symbols may still appear; no crash is the guarantee
        _ = findings
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

Expected: **BUILD FAILED** with errors naming `DriftSeverity`, `DriftFinding`,
and `TaskScanner`.

## Commit

```bash
git add tasks/task-243a-task-scanner-tests.md \
    MerlinTests/Unit/DriftSeverityTests.swift \
    MerlinTests/Unit/TaskScannerTests.swift
git commit -m "Task 243a — TaskScannerTests (failing)"
```
