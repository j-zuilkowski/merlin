# Phase 255a — WHY-Comment Pre-Commit Hook Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 254b complete: WhyCommentScanner real implementation live.

Introduces the WHY-comment pre-commit gate and the override-annotation parser.
The pre-commit hook (shell script installed by `GitHookInstaller`) calls `merlin-discipline
why-comment-check <projectPath>`. This phase wires up the Swift side: a `WHYCommentGate`
actor that produces a gate result used by the hook script.

New surface introduced in phase 255b:
  - `WHYCommentGate` actor in `Merlin/Discipline/WHYCommentGate.swift`:
    `func check(projectPath: String, adapter: ProjectAdapter) async -> WHYGateResult`
  - `WHYGateResult: Sendable` — `case pass`, `case block(violations: [WhyCommentTrigger])`.
  - Gate blocks when any trigger has `hasNearbyComment == false` AND is not suppressed by
    `rationale-not-needed:`. Gate passes when all triggers have comments or are suppressed.
  - `OverrideAnnotationParser` in `Merlin/Discipline/OverrideAnnotationParser.swift`:
    `func parse(line: String) -> OverrideAnnotation?`
  - `OverrideAnnotation: Sendable` — `rationale: String`.

TDD coverage:
  File 1 — `MerlinTests/Unit/WHYCommentGateTests.swift`: `check` returns `.block` when
    violations exist; `check` returns `.pass` when all violations have nearby comments;
    `check` returns `.pass` when all violations are suppressed by `rationale-not-needed`.
  File 2 — `MerlinTests/Unit/OverrideAnnotationParserTests.swift`: lines containing
    `rationale-not-needed: <text>` parse correctly; lines without the annotation return nil.

---

## Write to

- `MerlinTests/Unit/WHYCommentGateTests.swift`
- `MerlinTests/Unit/OverrideAnnotationParserTests.swift`

### MerlinTests/Unit/WHYCommentGateTests.swift

```swift
import XCTest
@testable import Merlin

final class WHYCommentGateTests: XCTestCase {

    private func makeAdapter(withTrigger regex: String) -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [WHYTriggerSpec(regex: regex, reason: "needs WHY comment")],
            manualCoveragePatterns: []
        )
    }

    private func makeTmpProject(sourceContent: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whygate-\(UUID())")
        let src = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try sourceContent.write(to: src.appendingPathComponent("S.swift"),
                                atomically: true, encoding: .utf8)
        return dir
    }

    // MARK: - block when violations present

    func testBlockWhenViolationsPresent() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething()
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .pass = result {
            XCTFail("Expected block when trigger has no nearby comment")
        }
    }

    // MARK: - pass when all violations have comments

    func testPassWhenCommentsPresent() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        // WHY: best-effort call, error discarded intentionally
        let x = try? doSomething()
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .block(let v) = result {
            XCTFail("Expected pass but got block with \(v.count) violations")
        }
    }

    // MARK: - pass when all violations suppressed

    func testPassWhenAllSuppressed() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething() // rationale-not-needed: safe
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .block(let v) = result {
            XCTFail("Expected pass but got block with \(v.count) violations")
        }
    }

    // MARK: - WHYGateResult is Sendable

    func testWHYGateResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(WHYGateResult.pass)
        requiresSendable(WHYGateResult.block(violations: []))
    }
}
```

### MerlinTests/Unit/OverrideAnnotationParserTests.swift

```swift
import XCTest
@testable import Merlin

final class OverrideAnnotationParserTests: XCTestCase {

    func testParsesRationaleNotNeeded() {
        let line = "let x = try? f() // rationale-not-needed: best-effort call"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNotNil(annotation)
        XCTAssertTrue(annotation?.rationale.contains("best-effort") == true)
    }

    func testReturnsNilForNormalLine() {
        let line = "let x = try? f()"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNil(annotation)
    }

    func testReturnsNilForUnrelatedComment() {
        let line = "let x = 42 // this is a normal comment"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNil(annotation)
    }

    func testAnnotationIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        let a = OverrideAnnotation(rationale: "test")
        requiresSendable(a)
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

Expected: **BUILD FAILED** with errors naming `WHYCommentGate`, `WHYGateResult`,
`OverrideAnnotationParser`, and `OverrideAnnotation`.

## Commit

```bash
git add tasks/task-255a-why-comment-hook-tests.md \
    MerlinTests/Unit/WHYCommentGateTests.swift \
    MerlinTests/Unit/OverrideAnnotationParserTests.swift
git commit -m "Phase 255a — WHYCommentGateTests (failing)"
```
