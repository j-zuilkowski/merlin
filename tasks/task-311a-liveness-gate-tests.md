# Phase 311a — LivenessGate Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 310b complete: `DocReferenceGraph` fenced-block strengthening landed.

Liveness Discipline batch, unit 5 of 6. The four liveness scanners (307–310) only
*report*. `LivenessGate` makes the deterministic part *prevent*: it runs
`TargetGateScanner` and blocks when a target is built by no scheme at all — a
zero-false-positive condition. Heuristic findings (stubs, unwired components) stay
advisory and never block a commit. Phase 311b also wires a `pre-commit` git hook so the
gate runs on every commit.

`LivenessGate` follows the existing `WHYCommentGate` / `ProseGate` pattern — an `actor`
in `Merlin/Discipline/`, pure Foundation.

New surface introduced in phase 311b:
  - `enum LivenessGateResult: Sendable, Equatable` — `.pass` / `.block([UngatedTargetFinding])`.
  - `actor LivenessGate` with
    `check(projectPath:gatingSchemes:) async -> LivenessGateResult`.
  - `DisciplineCLI` `pre-commit` subcommand; `GitHookInstaller` `pre-commit` hook script.

TDD coverage:
  `MerlinTests/Unit/LivenessGateTests.swift`.

---

## Write to: MerlinTests/Unit/LivenessGateTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 311a — failing tests for LivenessGate.
final class LivenessGateTests: XCTestCase {

    private func makeTmpProject(projectYML: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("livegate-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try projectYML.write(to: dir.appendingPathComponent("project.yml"),
                             atomically: true, encoding: .utf8)
        return dir
    }

    func testGateBlocksOnOrphanTarget() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          Orphan:
            type: framework
        schemes:
          App:
            build:
              targets:
                App: all
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let result = await LivenessGate().check(projectPath: proj.path, gatingSchemes: [])
        guard case .block(let orphans) = result else {
            return XCTFail("a target built by no scheme must block the gate")
        }
        XCTAssertTrue(orphans.contains { $0.targetName == "Orphan" })
    }

    func testGatePassesWhenEveryTargetIsBuilt() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
        schemes:
          App:
            build:
              targets:
                App: all
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let result = await LivenessGate().check(projectPath: proj.path, gatingSchemes: [])
        XCTAssertEqual(result, .pass)
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
Expected: **BUILD FAILED** — `LivenessGate` / `LivenessGateResult` do not exist yet.

## Commit
```
git add MerlinTests/Unit/LivenessGateTests.swift tasks/task-311a-liveness-gate-tests.md
git commit -m "Phase 311a — LivenessGate tests (failing)"
```
