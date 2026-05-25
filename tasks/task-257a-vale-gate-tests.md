# Task 257a — Vale Pre-Commit Gate Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 256b complete: ProseReadabilityChecker + ValeStyleWriter live.

Introduces the Vale pre-commit gate: a `ProseGate` actor that runs `ProseReadabilityChecker`
over changed `.md` files and blocks the commit if any exceeds its target grade.

New surface introduced in task 257b:
  - `ProseGate` actor in `Merlin/Discipline/ProseGate.swift`:
    `func check(changedDocFiles: [String], adapter: ProjectAdapter) async -> ProseGateResult`
  - `ProseGateResult: Sendable` — `case pass`,
    `case block(findings: [ReadabilityFinding])`.
  - Gate blocks when any `ReadabilityFinding.measuredGrade > targetGrade`. Target grade
    per file type is resolved from `adapter.docTargetGrade` by matching filename patterns:
    `user-manual` → 9, `developer-guide` → 9, `architecture` → 11, default → 9.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProseGateTests.swift`: when all docs are under target grade, gate
    passes; when one doc exceeds target, gate blocks with that finding; empty `changedDocFiles`
    always passes; `ProseGateResult` is `Sendable`.

---

## Write to

- `MerlinTests/Unit/ProseGateTests.swift`

### MerlinTests/Unit/ProseGateTests.swift

```swift
import XCTest
@testable import Merlin

final class ProseGateTests: XCTestCase {

    private func makeAdapter(grade: Double = 9.0) -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: ["user_manual": grade, "architecture": 11.0],
            whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    // MARK: - empty list always passes

    func testEmptyListPasses() async {
        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0)
        })
        let result = await gate.check(changedDocFiles: [], adapter: makeAdapter())
        if case .block(let findings) = result {
            XCTFail("Expected pass for empty list, got block: \(findings)")
        }
    }

    // MARK: - all docs under target passes

    func testAllUnderTargetPasses() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-manual-\(UUID()).md").path
        try "# Manual\n\nShort doc.".write(
            toFile: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: docFile) }

        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0) // under grade 9
        })
        let result = await gate.check(changedDocFiles: [docFile], adapter: makeAdapter())
        if case .block(let findings) = result {
            XCTFail("Expected pass but got block with \(findings.count) findings")
        }
    }

    // MARK: - doc over target blocks

    func testOverTargetBlocks() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-manual-hard-\(UUID()).md").path
        try "# Manual\n\nHard text.".write(
            toFile: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: docFile) }

        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 14.0) // over grade 9
        })
        let result = await gate.check(changedDocFiles: [docFile], adapter: makeAdapter())
        if case .pass = result {
            XCTFail("Expected block when grade exceeds target")
        }
    }

    // MARK: - ProseGateResult is Sendable

    func testProseGateResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(ProseGateResult.pass)
        requiresSendable(ProseGateResult.block(findings: []))
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

Expected: **BUILD FAILED** with errors naming `ProseGate`, `ProseGateResult`, and
`ProseGate.checkerFactory`.

## Commit

```bash
git add tasks/task-257a-vale-gate-tests.md \
    MerlinTests/Unit/ProseGateTests.swift
git commit -m "Task 257a — ProseGateTests (failing)"
```
