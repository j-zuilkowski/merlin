import XCTest
@testable import Merlin

/// Phase 331a - tests for `DisciplineExclusions`, the path blacklist every file-walking
/// discipline scanner honours. The `merlin-eval/` eval-suite tree holds deliberately-
/// buggy fixture source and scenario Markdown; without the blacklist the scanners raise
/// false drift / unwired / stub / dangling-reference findings against it.
final class DisciplineExclusionsTests: XCTestCase {

    // MARK: - The blacklist helper

    func testMerlinEvalIsInTheBlacklist() {
        XCTAssertTrue(
            DisciplineExclusions.excludedDirectoryNames.contains("merlin-eval"),
            "the eval-suite directory must be blacklisted")
    }

    func testPathInsideMerlinEvalIsExcluded() {
        let url = URL(fileURLWithPath:
            "/p/merlin/merlin-eval/fixtures/swift-gui-buggy/TaskBoard/TaskStore.swift")
        XCTAssertTrue(DisciplineExclusions.isExcluded(url))
    }

    func testNormalSourcePathIsNotExcluded() {
        let url = URL(fileURLWithPath: "/p/merlin/Merlin/Discipline/PhaseScanner.swift")
        XCTAssertFalse(DisciplineExclusions.isExcluded(url))
    }

    func testSimilarlyNamedFileIsNotExcluded() {
        // `merlin-eval` excludes a directory *component*, not every path containing the
        // substring - a file merely named `merlin-eval-notes.md` is still scanned.
        let url = URL(fileURLWithPath: "/p/merlin/docs/merlin-eval-notes.md")
        XCTAssertFalse(DisciplineExclusions.isExcluded(url))
    }

    // MARK: - Scanner wiring - a planted finding inside merlin-eval/ must be skipped

    /// A temp project tree whose only scanner-tripping content sits under `merlin-eval/`.
    /// With the blacklist wired into the scanners, each scan returns nothing.
    private func makeTempProject() throws -> String {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("disc-excl-\(UUID().uuidString)")
        let evalDir = root.appendingPathComponent("merlin-eval/fixtures")
        let appDir = root.appendingPathComponent("Merlin")
        try fm.createDirectory(at: evalDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)

        // Clean real source - trips no scanner.
        try "import Foundation\nstruct CleanType {}\n".write(
            to: appDir.appendingPathComponent("Clean.swift"),
            atomically: true, encoding: .utf8)

        // Fixture source that WOULD trip StubMarkerScanner (`fatalError`) and
        // ReachabilityScanner (an `@EnvironmentObject` dependency never injected) - but
        // lives under merlin-eval/, so the scanners must skip it.
        let fixture = """
        import SwiftUI
        final class GhostStore: ObservableObject {}
        struct GhostView: View {
            @EnvironmentObject var store: GhostStore
            var body: some View { Text("fixture") }
        }
        struct GhostHelper {
            func doWork() { fatalError("fixture placeholder") }
        }
        """
        try fixture.write(to: evalDir.appendingPathComponent("Buggy.swift"),
                          atomically: true, encoding: .utf8)
        return root.path
    }

    func testStubMarkerScannerSkipsMerlinEval() async throws {
        let path = try makeTempProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let findings = await StubMarkerScanner().scan(projectPath: path)
        XCTAssertTrue(findings.isEmpty,
            "StubMarkerScanner must skip merlin-eval/ - its only fatalError() is a fixture")
    }

    func testReachabilityScannerSkipsMerlinEval() async throws {
        let path = try makeTempProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let findings = await ReachabilityScanner().scan(projectPath: path)
        XCTAssertTrue(findings.isEmpty,
            "ReachabilityScanner must skip merlin-eval/ - GhostStore is a fixture")
    }
}
