# Task 310a — DocReferenceGraph Fenced-Block Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Task 309b complete: `ReachabilityScanner` wired into `DisciplineEngine`.

Liveness Discipline batch, unit 4 of 6. `FindingCategory.docStaleReference` already
exists — `DocReferenceGraph.danglingReferences` flags backticked doc identifiers absent
from source. It misses **enum-case names inside fenced code blocks**: that is exactly
how `versionBumpCandidate` lingered in `DeveloperManual.md` after task 301 deleted the
enum case — the case name was inside a ```` ```swift ```` block, not backticked.

Task 310b strengthens `danglingReferences` to also verify `case <name>` declarations
inside fenced code blocks, and raises the `docStaleReference` finding severity from
`.silent` to `.nudge` so stale docs surface on the discipline chip.

**This is a runtime-failure task.** The test compiles fine against the existing
`DocReferenceGraph.danglingReferences` API and FAILS at runtime because today's
implementation does not inspect fenced blocks. It MUST be verified with `test` (so the
test actually runs), not `build-for-testing`.

TDD coverage:
  `MerlinTests/Unit/DocReferenceGraphFencedBlockTests.swift`.

---

## Write to: MerlinTests/Unit/DocReferenceGraphFencedBlockTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 310a — failing test: a stale enum case inside a fenced doc code block must be
/// reported as a dangling reference.
final class DocReferenceGraphFencedBlockTests: XCTestCase {

    private func makeTmpProject(source: (String, String),
                                doc: (String, String)) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try source.1.write(to: dir.appendingPathComponent(source.0),
                           atomically: true, encoding: .utf8)
        try doc.1.write(to: dir.appendingPathComponent(doc.0),
                        atomically: true, encoding: .utf8)
        return dir
    }

    func testFencedCaseReferenceToMissingSymbolIsFlagged() async throws {
        let proj = try makeTmpProject(
            source: ("Model.swift", """
            enum Channel {
                case primary
                case secondary
            }
            """),
            doc: ("Manual.md", """
            # Manual

            The channel enum:

            ```swift
            enum Channel {
                case primary
                case secondary
                case ultraviolet
            }
            ```
            """))
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ultraviolet" },
                      "a fenced-block enum case absent from source must be flagged")
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "secondary" },
                       "a fenced-block enum case present in source must NOT be flagged")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphFencedBlockTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testFencedCaseReferenceToMissingSymbolIsFlagged` **FAILS** —
the current `danglingReferences` does not inspect fenced code blocks. Verified with
`test` (not `build-for-testing`) because the failure is at runtime, not compile time.

## Commit
```
git add MerlinTests/Unit/DocReferenceGraphFencedBlockTests.swift tasks/task-310a-doc-reference-fenced-block-tests.md
git commit -m "Task 310a — DocReferenceGraph fenced-block tests (failing)"
```
