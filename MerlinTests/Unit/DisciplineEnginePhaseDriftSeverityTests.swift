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

        // A `b` phase doc (read even before phase 323) declaring two surfaces:
        //  - ghostMethod()       — absent from source            -> red drift
        //  - driftMethod(a: Int) — present, signature differs     -> yellow drift
        let doc = """
        # Phase 701b — Drift Phase

        ## Context
        Test phase file.

        New surface introduced in phase 701b:
          - `func ghostMethod()` — absent surface
          - `func driftMethod(a: Int)` — drifted surface

        ---
        """
        try doc.write(
            to: proj.appendingPathComponent("phases/phase-701b-drift.md"),
            atomically: true, encoding: .utf8)
        try """
        import Foundation
        func driftMethod(b: String) { }
        """.write(
            to: proj.appendingPathComponent("Src/Code.swift"),
            atomically: true, encoding: .utf8)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            phaseScanner: PhaseScanner(),
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
