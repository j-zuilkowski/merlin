# Phase 243a — PhaseScanner Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 242b complete: ProjectConfig + ProjectConfigLoader live.

Introduces `PhaseScanner`, the load-bearing v2.2 component that validates phase files stay in
sync with the codebase. Builds a drift report classified into four colours.

New surface introduced in phase 243b:
  - `DriftSeverity: Sendable` enum — `case green, yellow, red, orange`.
  - `DriftFinding: Sendable, Identifiable` — `id: UUID`, `phaseID: String?`, `surface: String`,
    `severity: DriftSeverity`, `evidence: String`, `suggestedAction: String`.
  - `actor PhaseScanner` — `func scan(projectPath: String) async -> [DriftFinding]`.
  - PhaseScanner reads `phases/` directory, extracts "New surface introduced in phase NNb:"
    blocks from each NNb file, greps for each named symbol against the source tree:
    - green: symbol found, shape matches declaration.
    - yellow: symbol found but signature differs from declaration.
    - red: symbol absent from code (deleted without addendum).
    - orange: public symbol in code not declared in any phase file.

TDD coverage:
  File 1 — `MerlinTests/Unit/DriftSeverityTests.swift`: enum cases exist; `DriftFinding`
    conforms to `Identifiable` with UUID `id`; `DriftFinding` is `Sendable`.
  File 2 — `MerlinTests/Unit/PhaseScannerTests.swift`: scan of a tmp project with a phase NNb
    that declares "func fooBar()" but no such symbol in source returns a `.red` finding;
    a source file containing `func fooBar()` with a matching NNb declaration returns `.green`;
    a source file with an undeclared public symbol returns `.orange`; scanner handles empty
    phases/ directory without crashing.

---

## Write to

- `MerlinTests/Unit/DriftSeverityTests.swift`
- `MerlinTests/Unit/PhaseScannerTests.swift`

### MerlinTests/Unit/DriftSeverityTests.swift

```swift
import XCTest
@testable import Merlin

final class DriftSeverityTests: XCTestCase {

    func testAllCasesExist() {
        let cases: [DriftSeverity] = [.green, .yellow, .red, .orange]
        XCTAssertEqual(cases.count, 4)
    }

    func testDriftFindingIdentifiable() {
        let f = DriftFinding(
            id: UUID(),
            phaseID: "233b",
            surface: "ProviderBudget",
            severity: .red,
            evidence: "No match in source tree",
            suggestedAction: "Restore or write addendum"
        )
        // id must be the stable identifier
        XCTAssertNotNil(f.id)
    }

    func testDriftFindingIsSendable() {
        // Compile-time check: DriftFinding is Sendable
        func requiresSendable<T: Sendable>(_ value: T) {}
        let f = DriftFinding(
            id: UUID(),
            phaseID: nil,
            surface: "AgenticEngine",
            severity: .green,
            evidence: "Found at AgenticEngine.swift:12",
            suggestedAction: "No action needed"
        )
        requiresSendable(f)
    }
}
```

### MerlinTests/Unit/PhaseScannerTests.swift

```swift
import XCTest
@testable import Merlin

final class PhaseScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanproj-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let phasesDir = dir.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        return dir
    }

    private func writePhaseNNb(_ dir: URL, phaseID: String, surface: String) throws {
        let content = """
        # Phase \(phaseID) — Test Phase

        ## Context
        Test phase file.

        New surface introduced in phase \(phaseID):
          - `\(surface)` — test surface

        ---
        """
        let phasesDir = dir.appendingPathComponent("phases")
        try content.write(
            to: phasesDir.appendingPathComponent("phase-\(phaseID)-test.md"),
            atomically: true, encoding: .utf8)
    }

    private func writeSwiftSource(_ dir: URL, name: String, content: String) throws {
        let srcDir = dir.appendingPathComponent("Src")
        try content.write(
            to: srcDir.appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    // MARK: - red: symbol absent from code

    func testRedFindingWhenSymbolAbsent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writePhaseNNb(proj, phaseID: "99b", surface: "func fooBar()")
        // No matching source file

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let reds = findings.filter { $0.severity == .red }
        XCTAssertFalse(reds.isEmpty, "Expected at least one red finding for missing fooBar")
    }

    // MARK: - green: symbol present and declared

    func testGreenWhenSymbolPresent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writePhaseNNb(proj, phaseID: "99b", surface: "func fooBar()")
        try writeSwiftSource(proj, name: "FooBar", content: """
        import Foundation
        func fooBar() { }
        """)

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let greens = findings.filter { $0.severity == .green && $0.surface.contains("fooBar") }
        XCTAssertFalse(greens.isEmpty, "Expected green finding for present fooBar")
        let reds = findings.filter { $0.severity == .red && $0.surface.contains("fooBar") }
        XCTAssertTrue(reds.isEmpty, "Should not be red when symbol is present")
    }

    // MARK: - orange: public symbol not declared in any phase

    func testOrangeWhenUndeclaredPublicSymbol() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // No phase file declares "func undeclaredPublic()"
        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let oranges = findings.filter { $0.severity == .orange }
        XCTAssertFalse(oranges.isEmpty,
            "Expected orange finding for undeclared public symbol")
    }

    // MARK: - empty phases directory

    func testEmptyPhasesDirDoesNotCrash() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = PhaseScanner()
        // Should return without crashing
        let findings = await scanner.scan(projectPath: proj.path)
        // Orange findings for source symbols may still appear; no crash is the guarantee
        _ = findings
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

Expected: **BUILD FAILED** with errors naming `DriftSeverity`, `DriftFinding`,
and `PhaseScanner`.

## Commit

```bash
git add phases/phase-243a-phase-scanner-tests.md \
    MerlinTests/Unit/DriftSeverityTests.swift \
    MerlinTests/Unit/PhaseScannerTests.swift
git commit -m "Phase 243a — PhaseScannerTests (failing)"
```
