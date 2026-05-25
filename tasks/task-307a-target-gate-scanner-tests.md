# Phase 307a — TargetGateScanner Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.

This is the first phase of the **Liveness Discipline** batch (phases 307–312). Project
Discipline today catches *task drift* — spec/doc/code pulling apart. It is blind to
*liveness drift*: code that exists and compiles but is never reached, gated, or finished.
The `MerlinLiveTests` / `MerlinE2ETests` targets bit-rotted for ~160 phases precisely
because no scheme in the per-phase verification gate ever compiled them.

`TargetGateScanner` closes that gap: it reads `project.yml` and reports any target that
no scheme builds, or that only non-gating schemes build. It is a peer of `TaskScanner`,
`WhyCommentScanner`, etc. — an `actor` in `Merlin/Discipline/`, wired into
`DisciplineEngine` in phase 307b.

New surface introduced in phase 307b:
  - `UngatedTargetFinding` — `targetName: String`, `reason: String`, `blocking: Bool`.
  - `actor TargetGateScanner` with
    `scan(projectPath:gatingSchemes:) async -> [UngatedTargetFinding]`
    (`gatingSchemes` defaults to `[]`).
  - `FindingCategory.ungatedTarget` case.
  - `DisciplineEngine` wiring: a defaulted `targetGateScanner` init parameter and a
    conversion block in `scan(projectPath:)`.

TDD coverage:
  `MerlinTests/Unit/TargetGateScannerTests.swift` — a target in no scheme is flagged; a
  target built only by a non-gating scheme is flagged when `gatingSchemes` is set.

---

## Write to: MerlinTests/Unit/TargetGateScannerTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 307a — failing tests for TargetGateScanner.
final class TargetGateScannerTests: XCTestCase {

    private func makeTmpProject(projectYML: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("targetgate-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try projectYML.write(to: dir.appendingPathComponent("project.yml"),
                             atomically: true, encoding: .utf8)
        return dir
    }

    /// A target reachable by no scheme at all is flagged as blocking.
    func testOrphanTargetIsFlagged() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          AppTests:
            type: bundle.unit-test
          Orphan:
            type: framework
        schemes:
          App:
            build:
              targets:
                App: all
                AppTests: [test]
            test:
              targets: [AppTests]
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await TargetGateScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains { $0.targetName == "Orphan" && $0.blocking },
                      "a target in no scheme must be flagged as blocking")
        XCTAssertFalse(findings.contains { $0.targetName == "App" },
                       "a scheme-built target must not be flagged")
    }

    /// With gatingSchemes set, a target built only by a non-gating scheme is flagged.
    func testTargetOutsideGatingSchemeIsFlagged() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          LiveTests:
            type: bundle.unit-test
        schemes:
          App:
            build:
              targets:
                App: all
          Manual:
            build:
              targets:
                App: all
                LiveTests: [test]
            test:
              targets: [LiveTests]
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await TargetGateScanner()
            .scan(projectPath: proj.path, gatingSchemes: ["App"])
        XCTAssertTrue(findings.contains { $0.targetName == "LiveTests" && !$0.blocking },
                      "a target built only by a non-gating scheme must be flagged")
        XCTAssertFalse(findings.contains { $0.targetName == "App" })
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: **BUILD FAILED** — `TargetGateScanner` and `UngatedTargetFinding` do not exist
yet. This is a compile-failure phase (`build-for-testing` is the correct verb).

## Commit
```
git add MerlinTests/Unit/TargetGateScannerTests.swift tasks/task-307a-target-gate-scanner-tests.md
git commit -m "Phase 307a — TargetGateScanner tests (failing)"
```
