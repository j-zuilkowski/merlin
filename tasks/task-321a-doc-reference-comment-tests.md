# Task 321a — DocReferenceGraph Comment-Stripping Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 320b complete: WorkerDiffView toolbar buttons wired.

W4 trace audit finding F3: `DocReferenceGraph.extractEnumCaseNames` splits a `case` line
on commas **without first stripping a trailing `//` comment**. A comma inside the comment
is parsed as a case separator, so the comment's words become phantom "enum cases" and
`danglingReferences` reports them as stale doc references.

Live example — `spec.md:4546-4547`:
```
    case green       // surface present, shape unchanged
    case yellow      // surface present, signature changed (likely refactor)
```
yields phantom dangling references `shape` and `signature` (2 of the 4
`docStaleReference` findings in the current scan).

Task 321b fixes `extractEnumCaseNames` to drop the `//` comment before comma-splitting.

**This is a runtime-failure task.** The test compiles against the existing
`DocReferenceGraph.danglingReferences` API and FAILS at runtime (today's scanner reports
the phantom case). Verify with `test`.

TDD coverage: `MerlinTests/Unit/DocReferenceGraphCommentTests.swift`.

---

## Write to: MerlinTests/Unit/DocReferenceGraphCommentTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 321a — failing test for DocReferenceGraph comment-aware enum-case parsing.
final class DocReferenceGraphCommentTests: XCTestCase {

    /// Writes `[relativePath: content]`, creating intermediate directories.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-comment-\(UUID())", isDirectory: true)
        for (rel, content) in files {
            let fileURL = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testWordsInsideCaseLineCommentsAreNotFlagged() async throws {
        let proj = try makeTmpProject([
            "Manual.md": """
            # Manual
            ```swift
            enum Marker {
                case alpha   // first marker, commentword must be ignored
                case ghostFencedCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "commentword" },
                       "a word after a comma inside a // comment is not an enum case")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostFencedCase" },
                      "a genuine fenced enum case with no source symbol is still flagged")
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
  -only-testing:MerlinTests/DocReferenceGraphCommentTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testWordsInsideCaseLineCommentsAreNotFlagged` **FAILS**
against today's scanner (it reports the phantom `commentword` case). Verified with
`test` because the failure is at runtime.

## Commit
```
git add MerlinTests/Unit/DocReferenceGraphCommentTests.swift tasks/task-321a-doc-reference-comment-tests.md
git commit -m "Task 321a — DocReferenceGraphCommentTests (failing)"
```
