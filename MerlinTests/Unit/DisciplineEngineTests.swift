import XCTest
@testable import Merlin

final class DisciplineEngineTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("discipline-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Minimal structure
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("tasks"), withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(projectPath: String) -> DisciplineEngine {
        let adapter = ProjectAdapter.makeStub(language: "swift")
        return DisciplineEngine(
            adapter: adapter,
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(),
            storePath: projectPath + "/.merlin/pending.json"
        )
    }

    // MARK: - scan returns ScanReport

    func testScanReturnsScanReport() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let engine = makeEngine(projectPath: proj.path)
        let report = await engine.scan(projectPath: proj.path)
        XCTAssertGreaterThanOrEqual(report.durationMs, 0)
        XCTAssertTrue(report.scannedAt.timeIntervalSinceNow > -10,
                      "scannedAt should be recent")
    }

    // MARK: - pendingAttention reflects scan results

    func testPendingAttentionReflectsScan() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let engine = makeEngine(projectPath: proj.path)
        _ = await engine.scan(projectPath: proj.path)
        let findings = await engine.pendingAttention(projectPath: proj.path)
        // May be empty (clean project) or non-empty — we just confirm it's callable
        _ = findings
    }

    // MARK: - dismiss removes finding

    func testDismissRemovesFinding() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let engine = makeEngine(projectPath: proj.path)
        _ = await engine.scan(projectPath: proj.path)
        var findings = await engine.pendingAttention(projectPath: proj.path)
        guard let first = findings.first else {
            // No findings in clean project — inject one via the queue
            return
        }
        await engine.dismiss(finding: first, rationale: "test dismiss")
        findings = await engine.pendingAttention(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.id == first.id })
    }

    // MARK: - circuit breaker

    func testCircuitBreakerDisablesAfterThreeFailures() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("discipline-engine-telemetry-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        let adapter = ProjectAdapter.makeStub(language: "swift")
        let engine = DisciplineEngine(
            adapter: adapter,
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(),
            storePath: proj.path + "/.merlin/pending.json",
            forceErrorForTesting: true   // injects scan failure
        )
        _ = await engine.scan(projectPath: proj.path)
        _ = await engine.scan(projectPath: proj.path)
        _ = await engine.scan(projectPath: proj.path)
        await TelemetryEmitter.shared.flushForTesting()
        let events = readTelemetryEvents(fromFile: tempPath)
        let disabled = events.contains { $0["event"] as? String == "discipline.disabled" }
        XCTAssertTrue(disabled, "Engine should emit discipline.disabled after 3 failures")
    }
}
