# Phase 256a — ProseReadabilityChecker Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 255b complete: WHYCommentGate + OverrideAnnotationParser live.

Replaces the `ProseReadabilityChecker` stub with a real implementation. Calls `vale` (dev
tool, not vendored) with the Merlin-specific style folder. Includes Vale style file content.

New surface introduced in phase 256b (replacing stub):
  - `ProseReadabilityChecker.check(docFile:targetGrade:) async -> ReadabilityFinding`
    — real implementation. Runs `vale --output JSON <docFile>`, parses the output, returns
    measured grade and suggestions. In dry-run mode (init parameter), returns a synthetic
    result without spawning a process.
  - `ValeStyleWriter` in `Merlin/Discipline/ValeStyleWriter.swift`:
    `func writeStyles(to dir: String) async throws`
    — writes the Merlin Vale style files (`readability.yml`, `accept.txt`, `passive-voice.yml`,
    `weasel.yml`) to `dir/Merlin/`.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProseReadabilityCheckerTests.swift`:
    dry-run `check` returns a `ReadabilityFinding` with `docFile` matching the input;
    `measuredGrade` is non-negative; `targetGrade` matches the parameter; when `measuredGrade`
    exceeds `targetGrade`, suggestions is non-empty.
  File 2 — `MerlinTests/Unit/ValeStyleWriterTests.swift`:
    `writeStyles` creates `Merlin/readability.yml`, `Merlin/accept.txt` in the given dir.

---

## Write to

- `MerlinTests/Unit/ProseReadabilityCheckerTests.swift`
- `MerlinTests/Unit/ValeStyleWriterTests.swift`

### MerlinTests/Unit/ProseReadabilityCheckerTests.swift

```swift
import XCTest
@testable import Merlin

final class ProseReadabilityCheckerTests: XCTestCase {

    // MARK: - dry-run returns ReadabilityFinding

    func testDryRunReturnsFinding() async {
        let checker = ProseReadabilityChecker(dryRun: true)
        let finding = await checker.check(docFile: "/tmp/test.md", targetGrade: 9.0)
        XCTAssertEqual(finding.docFile, "/tmp/test.md")
        XCTAssertGreaterThanOrEqual(finding.measuredGrade, 0)
        XCTAssertEqual(finding.targetGrade, 9.0)
    }

    // MARK: - measuredGrade above targetGrade produces suggestions

    func testAboveTargetProducesSuggestions() async {
        // In dry-run mode with a forced high grade
        let checker = ProseReadabilityChecker(dryRun: true, forcedGrade: 14.0)
        let finding = await checker.check(docFile: "/tmp/hard.md", targetGrade: 9.0)
        XCTAssertGreaterThan(finding.measuredGrade, finding.targetGrade)
        XCTAssertFalse(finding.suggestions.isEmpty,
                       "Suggestions should be non-empty when grade exceeds target")
    }

    // MARK: - measuredGrade at or below target produces no suggestions

    func testAtOrBelowTargetNoSuggestions() async {
        let checker = ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0)
        let finding = await checker.check(docFile: "/tmp/easy.md", targetGrade: 9.0)
        XCTAssertLessThanOrEqual(finding.measuredGrade, finding.targetGrade)
        XCTAssertTrue(finding.suggestions.isEmpty,
                      "No suggestions expected when grade is at or below target")
    }

    // MARK: - ReadabilityFinding is Sendable

    func testReadabilityFindingIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        let f = ReadabilityFinding(docFile: "x.md", measuredGrade: 8, targetGrade: 9, suggestions: [])
        requiresSendable(f)
    }
}
```

### MerlinTests/Unit/ValeStyleWriterTests.swift

```swift
import XCTest
@testable import Merlin

final class ValeStyleWriterTests: XCTestCase {

    func testWriteStylesCreatesFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vale-styles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: dir.path)

        let merlinDir = dir.appendingPathComponent("Merlin")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: merlinDir.appendingPathComponent("readability.yml").path),
            "readability.yml should exist")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: merlinDir.appendingPathComponent("accept.txt").path),
            "accept.txt should exist")
    }

    func testWriteStylesIsIdempotent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vale-idem-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: dir.path)
        try await writer.writeStyles(to: dir.path) // second write should not throw
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

Expected: **BUILD FAILED** with errors naming `ProseReadabilityChecker(dryRun:forcedGrade:)`
and `ValeStyleWriter`.

## Commit

```bash
git add tasks/task-256a-prose-readability-tests.md \
    MerlinTests/Unit/ProseReadabilityCheckerTests.swift \
    MerlinTests/Unit/ValeStyleWriterTests.swift
git commit -m "Phase 256a — ProseReadabilityCheckerTests (failing)"
```
