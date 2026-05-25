# Phase 323a — TaskScanner Doc-Coverage & Drift-Severity Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 322 complete: dead TelemetryEmitter setters removed.

W4 trace audit finding F4. Two linked defects in the task-drift scanner:

1. **`TaskScanner` reads the wrong doc tier.** `extractDeclaredSurfaces` only reads
   files matching `task-\d+b-`. But the "New surface introduced in phase" block lives
   in the `a` (tests) doc per the project template — 200 of 263 `task-*a-*.md` carry it
   versus 8 of 266 `task-*b-*.md`. The `diag-*` series is excluded entirely. So the
   scanner sees almost no declared surface and flags ~210 `public` symbols as orange
   drift that are in fact task-documented.

2. **`DisciplineEngine` maps red drift to a commit-block.** `DisciplineEngine.scan`
   surfaces only `.red`/`.orange` drift and maps `.red → .block`. Once defect 1 is
   fixed the scanner reads ~200 historical task docs and finds genuine `.red` (symbol
   since refactored away) and `.yellow` (signature drifted) results. `.red → .block`
   would jam the live pre-commit gate on historical drift; `.yellow` is currently
   computed and silently discarded.

Phase 323b fixes both: `TaskScanner` reads all task docs (`a`, `b`, `diag-*`); the
engine surfaces `.red`/`.yellow`/`.orange` drift, all as `.nudge` (task drift is
advisory, never a commit-blocker).

**This is a runtime-failure phase.** The tests compile against existing APIs and FAIL
at runtime against today's behaviour. Verify with `test`.

TDD coverage:
  File 1 — TaskScannerDocCoverageTests: the scanner reads `a`-tier and `diag-*` docs.
  File 2 — DisciplineEnginePhaseDriftSeverityTests: drift findings are nudge, not block;
  yellow drift is surfaced.

---

## Write to: MerlinTests/Unit/TaskScannerDocCoverageTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 323a — failing tests: TaskScanner must read the `a` (tests) task docs and the
/// `diag-*` series, not only `task-NNb-*.md`. The "New surface introduced in phase"
/// block lives in the `a` doc per the project template.
final class TaskScannerDocCoverageTests: XCTestCase {

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phasedoc-cov-\(UUID())")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("phases"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Src"), withIntermediateDirectories: true)
        return dir
    }

    private func writeDoc(_ dir: URL, filename: String,
                          taskID: String, surface: String) throws {
        let content = """
        # Phase \(taskID) — Test Phase

        ## Context
        Test task file.

        New surface introduced in phase \(taskID):
          - `\(surface)` — test surface

        ---
        """
        try content.write(
            to: dir.appendingPathComponent("phases").appendingPathComponent(filename),
            atomically: true, encoding: .utf8)
    }

    private func writeSource(_ dir: URL, name: String, content: String) throws {
        try content.write(
            to: dir.appendingPathComponent("Src").appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    func testReadsNewSurfaceBlockFromTestsPhaseDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // The "New surface" block lives in the `a` (tests) doc per the template.
        try writeDoc(proj, filename: "task-700a-widget-tests.md",
                     taskID: "700a", surface: "func widgetMaker()")
        try writeSource(proj, name: "Widget", content: """
        import Foundation
        func widgetMaker() { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("widgetMaker") },
            "TaskScanner must read the New-surface block from the `a` (tests) task doc")
    }

    func testReadsNewSurfaceBlockFromDiagPhaseDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "diag-09a-probe-tests.md",
                     taskID: "09a", surface: "func diagProbe()")
        try writeSource(proj, name: "Probe", content: """
        import Foundation
        func diagProbe() { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("diagProbe") },
            "TaskScanner must read the diag-* task doc series")
    }
}
```

---

## Write to: MerlinTests/Unit/DisciplineEnginePhaseDriftSeverityTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 323a — failing test: DisciplineEngine must surface phaseDrift findings as
/// `.nudge` (never `.block`) and must surface `.yellow` signature-drift findings.
final class DisciplineEnginePhaseDriftSeverityTests: XCTestCase {

    func testPhaseDriftFindingsAreNudgeAndYellowIsSurfaced() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-sev-\(UUID())")
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("phases"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("Src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        // A `b` task doc (read even before phase 323) declaring two surfaces:
        //  - ghostMethod()       — absent from source            -> red drift
        //  - driftMethod(a: Int) — present, signature differs     -> yellow drift
        let doc = """
        # Phase 701b — Drift Phase

        ## Context
        Test task file.

        New surface introduced in phase 701b:
          - `func ghostMethod()` — absent surface
          - `func driftMethod(a: Int)` — drifted surface

        ---
        """
        try doc.write(
            to: proj.appendingPathComponent("tasks/task-701b-drift.md"),
            atomically: true, encoding: .utf8)
        try """
        import Foundation
        func driftMethod(b: String) { }
        """.write(
            to: proj.appendingPathComponent("Src/Code.swift"),
            atomically: true, encoding: .utf8)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: proj.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: proj.path)
        let drift = report.findings.filter { $0.category == .phaseDrift }

        XCTAssertTrue(drift.allSatisfy { $0.severity == .nudge },
                      "phaseDrift findings must be nudge severity — never block")
        XCTAssertTrue(drift.contains { $0.summary.contains("ghostMethod") },
                      "the red (absent-symbol) drift must still be surfaced, as a nudge")
        XCTAssertTrue(drift.contains { $0.summary.contains("driftMethod") },
                      "the yellow (signature-drift) finding must be surfaced")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TaskScannerDocCoverageTests \
  -only-testing:MerlinTests/DisciplineEnginePhaseDriftSeverityTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testReadsNewSurfaceBlockFromTestsPhaseDoc`,
`testReadsNewSurfaceBlockFromDiagPhaseDoc`, and
`testPhaseDriftFindingsAreNudgeAndYellowIsSurfaced` all **FAIL** against today's
behaviour. Verified with `test` because the failures are at runtime.

## Commit
```
git add MerlinTests/Unit/TaskScannerDocCoverageTests.swift \
  MerlinTests/Unit/DisciplineEnginePhaseDriftSeverityTests.swift \
  tasks/task-323a-phasescanner-doc-coverage-tests.md
git commit -m "Phase 323a — TaskScanner doc-coverage & drift-severity tests (failing)"
```
