# Task 324a — TaskScanner Symbol-Matching Accuracy Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 323b complete: `TaskScanner` now reads all task docs.

W4 trace audit finding F8 (surfaced by task 323). Once `TaskScanner` could see all
~200 task docs, the scan jumped 211 → 981 findings — but ~900 are false positives from
crude symbol matching, not real drift:
- **~400** — task docs declare members qualified (`AgenticEngine.invokeSkill(_:)`); the
  scanner stores only the bare `invokeSkill` from source, so the names never match.
- **~10** — enum cases declared as `.fail`; `TaskScanner` never enumerates `case`
  declarations from source at all, so every declared case reads as "absent → red".
- **~6** — non-symbol backtick content (`/compact`, `2.1.0`, `Notes.md`, `#high-stakes`)
  harvested from "New surface" blocks as if it were a code symbol.
- a large share of the `yellow` near-misses — a doc's bare `Foo` vs source `actor Foo`:
  `canonicalDeclaration` does not strip the declaration-kind keyword.

Task 324b fixes `TaskScanner` matching: `canonicalDeclaration` strips declaration-kind
keywords and leading `.`/`Type.` qualifiers; `extractSurfaces` ignores non-symbol
backtick content; `enumerateSourceDeclarations` records enum `case` declarations; and
`scan` treats **any name match as present (green)**. The old `yellow` "signature drift"
tier compared free-form doc signatures (selector style, `(...)`, full params) against
source declarations and was unreliable — a present symbol declared `foo(_:arguments:)`
in a doc must not read as drift. After 324, `red` means "declared symbol is gone" (the
actionable signal) and `green` means "present"; `yellow` is no longer produced.

**This is a runtime-failure task.** The tests compile against the existing
`TaskScanner.scan` API and FAIL at runtime against today's matching. Verify with `test`.

TDD coverage: `MerlinTests/Unit/TaskScannerMatchingTests.swift` — qualified member,
leading-dot enum case, non-symbol filtering, bare-type-name match, and a present symbol
with a notation-only signature difference.

---

## Write to: MerlinTests/Unit/TaskScannerMatchingTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 324a — failing tests for TaskScanner symbol-matching accuracy.
final class TaskScannerMatchingTests: XCTestCase {

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskmatch-\(UUID())")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(" tasks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Src"), withIntermediateDirectories: true)
        return dir
    }

    /// Writes a task doc whose "New surface" block lists `surfaces`, one bullet each.
    private func writeDoc(_ dir: URL, filename: String,
                          taskID: String, surfaces: [String]) throws {
        let bullets = surfaces.map { "  - `\($0)` — test surface" }
            .joined(separator: "\n")
        let content = """
        # Task \(taskID) — Test Task

        ## Context
        Test task file.

        New surface introduced in task \(taskID):
        \(bullets)

        ---
        """
        try content.write(
            to: dir.appendingPathComponent(" tasks").appendingPathComponent(filename),
            atomically: true, encoding: .utf8)
    }

    private func writeSource(_ dir: URL, name: String, content: String) throws {
        try content.write(
            to: dir.appendingPathComponent("Src").appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    /// A doc declaring a qualified member (`Type.method()`) must match the bare source
    /// declaration — not read as an absent symbol.
    func testQualifiedMemberMatchesBareSourceDeclaration() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-800a-widget-tests.md",
                     taskID: "800a", surfaces: ["WidgetMaker.assemble()"])
        try writeSource(proj, name: "Widget", content: """
        struct WidgetMaker {
            public func assemble() { }
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("assemble") },
            "a doc-declared `Type.member()` must match the bare source declaration")
        XCTAssertFalse(
            findings.contains { $0.severity == .red && $0.surface.contains("assemble") },
            "a qualified member that exists in source must not read as absent")
    }

    /// A doc declaring an enum case as `.caseName` must match a `case caseName` in source.
    func testLeadingDotEnumCaseMatchesSourceCase() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-801a-channel-tests.md",
                     taskID: "801a", surfaces: [".activeCase"])
        try writeSource(proj, name: "Channel", content: """
        enum Channel {
            case activeCase
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("activeCase") },
            "a doc-declared `.caseName` must match a `case caseName` in source")
        XCTAssertFalse(
            findings.contains { $0.severity == .red && $0.surface.contains("activeCase") },
            "an enum case that exists in source must not read as absent")
    }

    /// Non-symbol backtick content in a "New surface" block must not be scanned at all.
    func testNonSymbolBacktickContentIsIgnored() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-802a-misc-tests.md", taskID: "802a",
                     surfaces: ["/compact", "2.1.0", "Notes.md", "realThing()"])

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.surface.contains("/compact") },
                       "a slash-command is not a code symbol")
        XCTAssertFalse(findings.contains { $0.surface.contains("2.1.0") },
                       "a version string is not a code symbol")
        XCTAssertFalse(findings.contains { $0.surface.contains("Notes.md") },
                       "a file name is not a code symbol")
        XCTAssertTrue(findings.contains { $0.surface.contains("realThing") },
                      "a genuine declared symbol is still scanned (control)")
    }

    /// A doc declaring a bare type name must match `actor`/`struct`/`class Name` in
    /// source as green — not yellow (signature drift).
    func testBareTypeNameMatchesKeywordedDeclaration() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-803a-gadget-tests.md",
                     taskID: "803a", surfaces: ["GadgetService"])
        try writeSource(proj, name: "Gadget", content: """
        actor GadgetService { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("GadgetService") },
            "a bare `TypeName` doc surface must match `actor TypeName` as green")
        XCTAssertFalse(
            findings.contains { $0.severity == .yellow && $0.surface.contains("GadgetService") },
            "the declaration-kind keyword must not register as a signature difference")
    }

    /// A present symbol whose doc signature notation differs from source (selector
    /// style vs full params) is green — the symbol exists, so it is not drift.
    func testNameMatchWithDifferentSignatureIsGreen() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-804a-pipeline-tests.md",
                     taskID: "804a", surfaces: ["Pipeline.processItem(_:arguments:)"])
        try writeSource(proj, name: "Pipeline", content: """
        struct Pipeline {
            public func processItem(_ id: Int, arguments: [String]) { }
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("processItem") },
            "a declared symbol present in source is green even when the doc's signature "
            + "notation differs from the source declaration")
        XCTAssertFalse(
            findings.contains {
                ($0.severity == .red || $0.severity == .yellow)
                && $0.surface.contains("processItem")
            },
            "a present symbol must not read as drift on a notation-only signature diff")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TaskScannerMatchingTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; all five tests **FAIL** against today's matching. Verified
with `test` because the failures are at runtime.

## Commit
```
git add MerlinTests/Unit/TaskScannerMatchingTests.swift tasks/task-324a- taskscanner-matching-tests.md
git commit -m "Task 324a — TaskScanner symbol-matching tests (failing)"
```
