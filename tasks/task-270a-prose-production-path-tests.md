# Task 270a — Prose Readability Production Path Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 269b complete: adapter-key consistency fixed.

This task covers three High-priority prose-readability bugs. All touch existing
symbols, so the build will NOT fail — the new tests assert correct post-fix behaviour
and FAIL at runtime until task 270b lands.

**Bug A — Vale JSON parsing.** `ProseReadabilityChecker.extractGrade` reads
`obj["readability"]` as a top-level `Double`. Vale's real `--output JSON` output has no
such key — it is a dictionary keyed by file path whose values are arrays of alert
objects. `extractGrade` therefore always returns `nil`, the checker always falls back to
`targetGrade`, and `ProseGate` never blocks anything.

**Bug B — Vale style file shape.** `ValeStyleWriter`'s `readability.yml` uses
`extends: existence` — `existence` is a token-matching rule, not a readability rule.
Vale never computes a grade from it.

**Bug C — checker unused.** `DisciplineEngine` stores `proseReadabilityChecker` as a
dependency but never invokes it in `scan()`. Prose readability is dead in the engine.

New surface introduced in task 270b:
  - `ValeStyleWriter` `readability.yml` uses `extends: readability` (with a `metrics:`
    list and a `grade:` threshold), not `extends: existence`.
  - `ProseReadabilityChecker.extractGrade` / `extractSuggestions` parse Vale's actual
    JSON output (dictionary keyed by file path → array of alert objects). The
    `dryRun` / `forcedGrade` test seam is unchanged.
  - `DisciplineEngine.scan()` enumerates `*.md` doc files, computes each file's target
    grade, runs `proseReadabilityChecker.check(...)`, and emits a `proseReadabilityFail`
    finding (severity `.nudge`) per file whose `measuredGrade > targetGrade`.

TDD coverage:
  File 1 — `ProseProductionPathTests.swift`:
    - `ValeStyleWriter`-written `readability.yml` contains `extends: readability` and
      does NOT contain `extends: existence`.
    - A `DisciplineEngine` built with an injected
      `ProseReadabilityChecker(dryRun: true, forcedGrade: 15.0)` and a temp project
      containing a `.md` file emits at least one `proseReadabilityFail` finding.

---

## Write to: MerlinTests/Unit/ProseProductionPathTests.swift

```swift
import XCTest
@testable import Merlin

final class ProseProductionPathTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Vale style file shape

    func testReadabilityStyleUsesReadabilityRule() async throws {
        let styleDir = projectRoot.appendingPathComponent("styles")
        try FileManager.default.createDirectory(
            at: styleDir, withIntermediateDirectories: true)

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: styleDir.path)

        let readabilityURL = styleDir
            .appendingPathComponent("Merlin")
            .appendingPathComponent("readability.yml")
        let yaml = try String(contentsOf: readabilityURL, encoding: .utf8)

        XCTAssertTrue(yaml.contains("extends: readability"),
            "readability.yml must use Vale's real readability rule")
        XCTAssertFalse(yaml.contains("extends: existence"),
            "readability.yml must not use the existence (token-matching) rule")
    }

    // MARK: - DisciplineEngine runs the prose checker

    func testEngineEmitsProseReadabilityFinding() async throws {
        try writeFile("docs/guide.md", """
        # Guide

        This document contains prose that the readability checker will grade.
        """)

        // forcedGrade 15.0 is well above any target → must produce a fail finding.
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(
                dryRun: true, forcedGrade: 15.0),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: projectRoot.path)
        let proseFindings = report.findings.filter {
            $0.category == .proseReadabilityFail
        }

        XCTAssertFalse(proseFindings.isEmpty,
            "scan() must run the prose checker and emit a proseReadabilityFail " +
            "finding for a doc that exceeds its target grade")
        XCTAssertEqual(proseFindings.first?.severity, .nudge)
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, but `ProseProductionPathTests` FAILS at runtime —
`readability.yml` still uses `extends: existence`, and `DisciplineEngine.scan()` never
runs the prose checker. Task 270b makes both cases pass.

## Commit

```bash
git add tasks/task-270a-prose-production-path-tests.md \
    MerlinTests/Unit/ProseProductionPathTests.swift
git commit -m "Task 270a — ProseProductionPathTests (failing)"
```
