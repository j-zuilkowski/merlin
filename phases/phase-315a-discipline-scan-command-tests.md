# Phase 315a — `merlin-discipline scan` Command Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 314b complete: `TargetGateScanner` follows transitive dependencies.

The `merlin-discipline` CLI has `pre-commit`, `post-commit`, `pre-push` — all gates.
There is **no way to simply run the full discipline scan and see every finding**. An
operator (and the W2 triage step of the proving-readiness plan) needs that. This phase
adds a `scan` subcommand: it runs `DisciplineEngine.scan()` and prints every finding,
grouped by category. `scan` is informational — it always exits 0, it never blocks.

New surface introduced in phase 315b:
  - `DisciplineCLI.formatScanReport(_ findings: [Finding]) -> String` — `internal static`
    pure formatter (the unit-tested seam).
  - `DisciplineCLI` `scan` subcommand → `runScan(projectPath:)`.

TDD coverage:
  `MerlinTests/Unit/DisciplineScanReportTests.swift` — `formatScanReport` groups
  findings by category and handles the empty case.

---

## Write to: MerlinTests/Unit/DisciplineScanReportTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 315a — failing tests for the `merlin-discipline scan` report formatter.
final class DisciplineScanReportTests: XCTestCase {

    private func finding(_ category: FindingCategory,
                         _ severity: Severity,
                         summary: String) -> Finding {
        Finding(id: UUID(), category: category, severity: severity,
                summary: summary, detail: "detail for \(summary)",
                suggestedAction: nil, createdAt: Date(), lastSeenAt: Date())
    }

    func testScanReportGroupsFindingsByCategory() {
        let findings = [
            finding(.ungatedTarget, .block, summary: "OrphanTarget"),
            finding(.stubbedImplementation, .nudge, summary: "Foo.swift:10"),
        ]
        let report = DisciplineCLI.formatScanReport(findings)
        XCTAssertTrue(report.contains("ungatedTarget"),
                      "report must name each finding category")
        XCTAssertTrue(report.contains("OrphanTarget"),
                      "report must include each finding's summary")
        XCTAssertTrue(report.contains("stubbedImplementation"))
    }

    func testScanReportHandlesNoFindings() {
        let report = DisciplineCLI.formatScanReport([])
        XCTAssertFalse(report.isEmpty,
                       "an empty scan must still print a summary line")
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
Expected: **BUILD FAILED** — `DisciplineCLI.formatScanReport` does not exist yet. This
is a compile-failure phase (`build-for-testing` is the correct verb).

## Commit
```
git add MerlinTests/Unit/DisciplineScanReportTests.swift phases/phase-315a-discipline-scan-command-tests.md
git commit -m "Phase 315a — merlin-discipline scan command tests (failing)"
```
