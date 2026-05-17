# Phase 331a — Discipline Exclusions Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 330 complete: phases 326–330 are the eval harness (capability + surface + render +
operator coverage).

Reason for this phase: the eval suite's fixture tree, `merlin-eval/`, is about to be
moved *into* the merlin repo (phase 332). It contains deliberately-buggy fixture source
(`.swift`, `.rs`) and scenario Markdown. Every file-walking discipline scanner is handed
the **repo root** and would then walk `merlin-eval/`, raising false drift / unwired /
stub / dangling-reference findings. This phase adds the failing tests for
`DisciplineExclusions` — a shared path blacklist the scanners will honour (phase 331b).

New surface introduced in phase 331b:
  - `DisciplineExclusions.excludedDirectoryNames: Set<String>` — the blacklist; initially
    `["merlin-eval"]`.
  - `DisciplineExclusions.isExcluded(_ url: URL) -> Bool` — true when `url` lies inside a
    blacklisted directory (path-component match, not substring).

TDD coverage:
  File 1 — `DisciplineExclusionsTests`: unit tests for the blacklist helper, plus two
  end-to-end wiring tests (StubMarkerScanner, ReachabilityScanner) proving a planted
  finding inside a `merlin-eval/` subtree is skipped. The remaining six wiring sites use
  the identical one-line predicate and are grep-verified in 331b.

---

## Write to: MerlinTests/Unit/DisciplineExclusionsTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 331a — tests for `DisciplineExclusions`, the path blacklist every file-walking
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
        // substring — a file merely named `merlin-eval-notes.md` is still scanned.
        let url = URL(fileURLWithPath: "/p/merlin/docs/merlin-eval-notes.md")
        XCTAssertFalse(DisciplineExclusions.isExcluded(url))
    }

    // MARK: - Scanner wiring — a planted finding inside merlin-eval/ must be skipped

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

        // Clean real source — trips no scanner.
        try "import Foundation\nstruct CleanType {}\n".write(
            to: appDir.appendingPathComponent("Clean.swift"),
            atomically: true, encoding: .utf8)

        // Fixture source that WOULD trip StubMarkerScanner (`fatalError`) and
        // ReachabilityScanner (an `@EnvironmentObject` dependency never injected) — but
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
            "StubMarkerScanner must skip merlin-eval/ — its only fatalError() is a fixture")
    }

    func testReachabilityScannerSkipsMerlinEval() async throws {
        let path = try makeTempProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let findings = await ReachabilityScanner().scan(projectPath: path)
        XCTAssertTrue(findings.isEmpty,
            "ReachabilityScanner must skip merlin-eval/ — GhostStore is a fixture")
    }
}
```

---

## Verify
```
cd ~/Documents/localProject/merlin
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — errors "cannot find 'DisciplineExclusions' in scope" (four
references). `StubMarkerScanner` / `ReachabilityScanner` already exist, so the *only*
compile errors name `DisciplineExclusions`. That is the failing-tests state.

## Commit
```
git add MerlinTests/Unit/DisciplineExclusionsTests.swift \
        phases/phase-331a-discipline-exclusions-tests.md
git commit -m "Phase 331a — DisciplineExclusionsTests (failing)"
```
