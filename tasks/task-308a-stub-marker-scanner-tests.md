# Phase 308a — StubMarkerScanner Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 307b complete: `TargetGateScanner` wired into `DisciplineEngine`.

Liveness Discipline batch, unit 2 of 6. `StubMarkerScanner` finds stub, placeholder, and
deferred-work markers — features that compile green but are unfinished. It would have
caught the three dead `{}` View-menu commands fixed in phase 305.

New surface introduced in phase 308b:
  - `StubMarkerFinding` — `file: String`, `line: Int`, `marker: String`,
    `isHardStub: Bool`, `context: String`.
  - `actor StubMarkerScanner` with `scan(projectPath:) async -> [StubMarkerFinding]`.
  - `FindingCategory.stubbedImplementation` case.
  - `DisciplineEngine` wiring (defaulted `stubMarkerScanner` parameter + conversion block).

TDD coverage:
  `MerlinTests/Unit/StubMarkerScannerTests.swift` — a `fatalError` is flagged as a hard
  stub; a `TODO` comment is flagged as a deferral marker; markers under `Tests/` are
  skipped.

---

## Write to: MerlinTests/Unit/StubMarkerScannerTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 308a — failing tests for StubMarkerScanner.
final class StubMarkerScannerTests: XCTestCase {

    private func makeTmpProject(file: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubscan-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent(file),
                          atomically: true, encoding: .utf8)
        return dir
    }

    func testHardStubsAndDeferralMarkersAreFound() async throws {
        let proj = try makeTmpProject(file: "Source.swift", content: """
        import Foundation
        func unfinished() {
            fatalError("wire this up")
        }
        // TODO: implement caching
        let ready = true
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains { $0.marker == "fatalError" && $0.isHardStub },
                      "fatalError must be flagged as a hard stub")
        XCTAssertTrue(findings.contains { $0.marker == "TODO" && !$0.isHardStub },
                      "a TODO comment must be flagged as a deferral marker")
    }

    func testTestDirectoriesAreSkipped() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubscan-\(UUID())", isDirectory: true)
        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(
            at: testsDir, withIntermediateDirectories: true)
        try "// TODO: not a production stub\nlet x = 1\n"
            .write(to: testsDir.appendingPathComponent("FooTests.swift"),
                   atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let findings = await StubMarkerScanner().scan(projectPath: dir.path)
        XCTAssertTrue(findings.isEmpty, "markers under Tests/ must be skipped")
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
Expected: **BUILD FAILED** — `StubMarkerScanner` / `StubMarkerFinding` do not exist yet.

## Commit
```
git add MerlinTests/Unit/StubMarkerScannerTests.swift tasks/task-308a-stub-marker-scanner-tests.md
git commit -m "Phase 308a — StubMarkerScanner tests (failing)"
```
