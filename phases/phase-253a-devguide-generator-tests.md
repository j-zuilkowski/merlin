# Phase 253a — DevGuideGenerator Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 252b complete: APIDocGenerator live.

Introduces `DevGuideGenerator` which regenerates the mechanical sections of
`developer-guide.md` — build commands, test commands, adapter config — directly from the
project adapter, keeping the guide in sync without manual edits.

New surface introduced in phase 253b:
  - `DevGuideGenerator` actor in `Merlin/Discipline/DevGuideGenerator.swift`:
    `func generate(projectPath: String, adapter: ProjectAdapter) async throws`
    — updates the "mechanical sections" of `docs/developer-guide.md` (or creates the file if
    absent). Mechanical sections are delimited by `<!-- dev-guide:begin:SECTION -->` and
    `<!-- dev-guide:end:SECTION -->` markers. Content between markers is replaced; prose
    outside is preserved.
    `func mechanicalSections(adapter: ProjectAdapter) -> [String: String]`
    — returns `{sectionName → content}` for `build`, `test`, `versioning`, `adapter`.

TDD coverage:
  File 1 — `MerlinTests/Unit/DevGuideGeneratorTests.swift`:
    `mechanicalSections` includes a "build" entry containing `adapter.buildCommand`;
    `generate` writes the developer guide when absent; `generate` replaces only content inside
    markers, preserving prose outside; calling `generate` twice is idempotent (same output).

---

## Write to

- `MerlinTests/Unit/DevGuideGeneratorTests.swift`

### MerlinTests/Unit/DevGuideGeneratorTests.swift

```swift
import XCTest
@testable import Merlin

final class DevGuideGeneratorTests: XCTestCase {

    private func makeAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild -scheme Merlin build-for-testing",
            testCommand: "xcodebuild -scheme MerlinTests test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    // MARK: - mechanicalSections includes build command

    func testMechanicalSectionsIncludesBuildCommand() async {
        let gen = DevGuideGenerator()
        let adapter = makeAdapter()
        let sections = await gen.mechanicalSections(adapter: adapter)
        guard let build = sections["build"] else {
            XCTFail("Missing 'build' section"); return
        }
        XCTAssertTrue(build.contains(adapter.buildCommand),
                      "Build section should contain the adapter build command")
    }

    // MARK: - generate creates file when absent

    func testGenerateCreatesFileWhenAbsent() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = DevGuideGenerator()
        try await gen.generate(projectPath: proj.path, adapter: makeAdapter())

        let guide = docsDir.appendingPathComponent("developer-guide.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: guide.path))
        let text = try String(contentsOf: guide, encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: - generate preserves prose outside markers

    func testGeneratePreservesProse() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-prose-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let guide = docsDir.appendingPathComponent("developer-guide.md")
        let existingProse = """
        # Developer Guide

        ## Introduction

        This guide explains how to contribute.

        <!-- dev-guide:begin:build -->
        old content
        <!-- dev-guide:end:build -->

        ## Architecture

        See architecture.md for the full design.
        """
        try existingProse.write(to: guide, atomically: true, encoding: .utf8)

        let gen = DevGuideGenerator()
        try await gen.generate(projectPath: proj.path, adapter: makeAdapter())

        let updated = try String(contentsOf: guide, encoding: .utf8)
        XCTAssertTrue(updated.contains("This guide explains how to contribute."),
                      "Prose outside markers should be preserved")
        XCTAssertTrue(updated.contains("See architecture.md"),
                      "Tail prose should be preserved")
        XCTAssertFalse(updated.contains("old content"),
                       "Old mechanical content should be replaced")
    }

    // MARK: - generate is idempotent

    func testGenerateIsIdempotent() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-idem-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = DevGuideGenerator()
        let adapter = makeAdapter()
        try await gen.generate(projectPath: proj.path, adapter: adapter)
        let first = try String(contentsOf: docsDir.appendingPathComponent("developer-guide.md"),
                               encoding: .utf8)
        try await gen.generate(projectPath: proj.path, adapter: adapter)
        let second = try String(contentsOf: docsDir.appendingPathComponent("developer-guide.md"),
                                encoding: .utf8)
        XCTAssertEqual(first, second, "Second generate should produce identical output")
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

Expected: **BUILD FAILED** with errors naming `DevGuideGenerator` and
`DevGuideGenerator.mechanicalSections`.

## Commit

```bash
git add phases/phase-253a-devguide-generator-tests.md \
    MerlinTests/Unit/DevGuideGeneratorTests.swift
git commit -m "Phase 253a — DevGuideGeneratorTests (failing)"
```
