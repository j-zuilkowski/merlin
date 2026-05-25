# Phase 249a — ManualCoverageScanner Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 248b complete: GitHookInstaller live.

Replaces the `ManualCoverageScanner` stub (from phase 245b) with a real implementation.
The scanner enumerates user-facing surfaces via adapter regex patterns, then reads
`<!-- covers: ... -->` blocks from doc files to build the coverage map.

New surface introduced in phase 249b (replacing stub):
  - `ManualCoverageScanner.scan(projectPath:adapter:)` — real implementation that:
    1. Greps source files for adapter `manualCoveragePatterns` regexes.
    2. Reads all `.md` doc files for `<!-- covers: ... -->` blocks.
    3. Returns `[ManualCoverageGap]` for surfaces not covered by any doc block.
  - `ManualCoverageScanner.buildCoverageMap(projectPath:adapter:) async -> [String: [String]]`
    — `surface → [docFile]` map, used by release gate.
  - `// manual: not-user-facing` inline annotation suppresses coverage requirement for a
    surface. The scanner recognises this marker and excludes matching surfaces.

TDD coverage:
  File 1 — `MerlinTests/Unit/ManualCoverageScannerTests.swift`:
    A source file with `SkillRegistry.register("foo")` and no matching `<!-- covers: -->` block
    returns a gap for `foo`; adding a covers block for that surface removes the gap; a source
    line annotated `// manual: not-user-facing` is excluded; `buildCoverageMap` returns the
    correct doc file associations.

---

## Write to

- `MerlinTests/Unit/ManualCoverageScannerTests.swift`

### MerlinTests/Unit/ManualCoverageScannerTests.swift

```swift
import XCTest
@testable import Merlin

final class ManualCoverageScannerTests: XCTestCase {

    private func makeAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild",
            testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED",
            buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create",
            apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [],
            manualCoveragePatterns: [
                ManualCoveragePattern(type: "slash_command", regex: "SkillRegistry\\.register")
            ]
        )
    }

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let docDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Uncovered surface produces gap

    func testUncoveredSurfaceProducesGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("my-feature")
        """.write(to: proj.appendingPathComponent("Src/Feature.swift"),
                  atomically: true, encoding: .utf8)

        // No doc file with covers block

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertFalse(gaps.isEmpty, "Expected gap for uncovered SkillRegistry.register surface")
    }

    // MARK: - Covered surface produces no gap

    func testCoveredSurfaceProducesNoGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("my-feature")
        """.write(to: proj.appendingPathComponent("Src/Feature.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # User Manual

        ## My Feature

        <!-- covers:
             - SkillRegistry.register("my-feature")
        -->

        Description here.
        """.write(to: proj.appendingPathComponent("docs/user-manual.md"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertTrue(gaps.isEmpty,
            "No gaps expected when surface is covered by docs")
    }

    // MARK: - not-user-facing annotation suppresses requirement

    func testNotUserFacingAnnotationSuppressesGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        // manual: not-user-facing — internal hook only
        SkillRegistry.register("internal-hook")
        """.write(to: proj.appendingPathComponent("Src/Internal.swift"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertTrue(gaps.isEmpty,
            "not-user-facing annotation should suppress coverage requirement")
    }

    // MARK: - buildCoverageMap

    func testBuildCoverageMap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("mapped-feature")
        """.write(to: proj.appendingPathComponent("Src/Mapped.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # Manual

        <!-- covers:
             - SkillRegistry.register("mapped-feature")
        -->
        """.write(to: proj.appendingPathComponent("docs/user-manual.md"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let map = await scanner.buildCoverageMap(projectPath: proj.path, adapter: makeAdapter())
        // At least one surface should map to a doc file
        XCTAssertFalse(map.isEmpty, "Coverage map should have entries")
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

Expected: **BUILD FAILED** with errors naming `ManualCoverageScanner.buildCoverageMap`
(the stub does not have this method).

## Commit

```bash
git add tasks/task-249a-manual-coverage-scanner-tests.md \
    MerlinTests/Unit/ManualCoverageScannerTests.swift
git commit -m "Phase 249a — ManualCoverageScannerTests (failing)"
```
