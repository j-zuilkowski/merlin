# Phase 250a — Manual Baseline Decay Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 249b complete: ManualCoverageScanner full implementation live.

Introduces the decaying baseline mechanism that allows `/project:adopt` to grandfather existing
gaps while enforcing forward progress. Also introduces manual section template writing.

New surface introduced in phase 250b:
  - `ManualBaselineManager` actor in `Merlin/Discipline/ManualBaselineManager.swift`:
    `func currentBaseline(projectPath: String) async -> Int`
    `func recordRelease(projectPath: String, uncoveredCount: Int) async throws`
    `func releaseGateCheck(projectPath: String, uncoveredCount: Int,
     config: ProjectConfig) async -> BaselineCheckResult`
  - `BaselineCheckResult: Sendable` — `case pass`, `case fail(reason: String)`.
  - `ManualSectionTemplateWriter` in `Merlin/Discipline/ManualSectionTemplateWriter.swift`:
    `func write(gap: ManualCoverageGap, to docPath: String) async throws`
  - `recordRelease` appends a baseline snapshot to `.merlin/manual-coverage-baseline.json`.
    `releaseGateCheck` returns `.fail` if (a) any new surfaces are uncovered relative to the
    last snapshot, or (b) uncoveredCount > baseline - decayPerRelease.

TDD coverage:
  File 1 — `MerlinTests/Unit/ManualBaselineDecayTests.swift`:
    First release with baseline=0 passes; second release with 5 new uncovered surfaces fails;
    release that reduces uncovered count by at least decayPerRelease passes; release at same
    baseline as previous fails (no decay progress).
  File 2 — `MerlinTests/Unit/ManualSectionTemplateWriterTests.swift`:
    `write(gap:to:)` appends a non-empty markdown section to the given doc file; the section
    contains the surface name; calling write twice with the same surface does not duplicate.

---

## Write to

- `MerlinTests/Unit/ManualBaselineDecayTests.swift`
- `MerlinTests/Unit/ManualSectionTemplateWriterTests.swift`

### MerlinTests/Unit/ManualBaselineDecayTests.swift

```swift
import XCTest
@testable import Merlin

final class ManualBaselineDecayTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-\(UUID())")
        let dotMerlin = dir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        return dir
    }

    private func makeConfig(baseline: Int, decay: Int) -> ProjectConfig {
        ProjectConfig(adapter: "swift-xcode", adapterVersion: "1.0",
                      disciplineLayers: ["soft_prompt"],
                      manualCoverageBaseline: baseline, decayPerRelease: decay)
    }

    // MARK: - First release with baseline 0 passes

    func testFirstReleasePassesWithZeroBaseline() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 0, decay: 10)
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 0, config: config)
        if case .fail(let reason) = result {
            XCTFail("Expected pass but got fail: \(reason)")
        }
    }

    // MARK: - New uncovered surfaces fail

    func testNewUncoveredSurfacesFail() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 10, decay: 5)
        // Record a snapshot at 10
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 10)
        // Now check with 15 — new surfaces appeared
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 15, config: config)
        if case .pass = result {
            XCTFail("Expected fail when uncovered count increased")
        }
    }

    // MARK: - Release that reduces by >= decayPerRelease passes

    func testDecayProgressPasses() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 20, decay: 10)
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 20)
        // Reduced by 10 — meets decay requirement
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 10, config: config)
        if case .fail(let reason) = result {
            XCTFail("Expected pass with adequate decay but got: \(reason)")
        }
    }

    // MARK: - No decay progress fails

    func testNoDecayProgressFails() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 20, decay: 10)
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 20)
        // Same count as previous — no progress
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 20, config: config)
        if case .pass = result {
            XCTFail("Expected fail when baseline did not decay")
        }
    }

    // MARK: - BaselineCheckResult is Sendable

    func testBaselineCheckResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(BaselineCheckResult.pass)
        requiresSendable(BaselineCheckResult.fail(reason: "test"))
    }
}
```

### MerlinTests/Unit/ManualSectionTemplateWriterTests.swift

```swift
import XCTest
@testable import Merlin

final class ManualSectionTemplateWriterTests: XCTestCase {

    private func makeGap(surface: String) -> ManualCoverageGap {
        ManualCoverageGap(surface: surface, surfaceType: "slash_command",
                          firstSeen: Date(), suggestedSection: nil)
    }

    // MARK: - write appends a markdown section

    func testWriteAppendsSection() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-\(UUID()).md")
        try "# User Manual\n\n".write(to: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: docFile) }

        let writer = ManualSectionTemplateWriter()
        try await writer.write(gap: makeGap(surface: "SkillRegistry.register(\"dark-mode\")"),
                               to: docFile.path)

        let text = try String(contentsOf: docFile, encoding: .utf8)
        XCTAssertTrue(text.contains("dark-mode") || text.contains("SkillRegistry"),
                      "Section should contain the surface name")
        XCTAssertTrue(text.count > 20, "Section should be non-empty")
    }

    // MARK: - write does not duplicate on second call

    func testWriteDoesNotDuplicate() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-\(UUID()).md")
        try "# User Manual\n\n".write(to: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: docFile) }

        let writer = ManualSectionTemplateWriter()
        let gap = makeGap(surface: "SomeFeature")
        try await writer.write(gap: gap, to: docFile.path)
        try await writer.write(gap: gap, to: docFile.path)

        let text = try String(contentsOf: docFile, encoding: .utf8)
        // Count occurrences of the covers marker for SomeFeature
        let count = text.components(separatedBy: "SomeFeature").count - 1
        XCTAssertEqual(count, 1, "Surface should appear exactly once in doc")
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

Expected: **BUILD FAILED** with errors naming `ManualBaselineManager`, `BaselineCheckResult`,
and `ManualSectionTemplateWriter`.

## Commit

```bash
git add tasks/task-250a-manual-baseline-decay-tests.md \
    MerlinTests/Unit/ManualBaselineDecayTests.swift \
    MerlinTests/Unit/ManualSectionTemplateWriterTests.swift
git commit -m "Phase 250a — ManualBaselineDecayTests (failing)"
```
