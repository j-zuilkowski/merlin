# Task 316a — DocReferenceGraph Scope Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

> **Note:** the test file from this task is rewritten by task 319b. Use 319b's version.

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Task 315b complete: `merlin-discipline scan` exists.

The first real `merlin-discipline scan` of the Merlin repo produced 1578
`docStaleReference` findings — ~99% false positives. Two root causes:
  1. `danglingReferences` scans `tasks/*.md` — build scaffolding full of historical and
     illustrative identifiers (1130 of the findings cite a `tasks/` doc).
  2. `enumerateSourceSymbols` excludes `Tests/`, so a doc that legitimately names a test
     class is reported as a dangling reference to a missing symbol.

Task 316b fixes both: skip `tasks/` entirely in `danglingReferences`, and include test
files in the source-symbol set.

**This is a runtime-failure task.** The test compiles against the existing
`DocReferenceGraph.danglingReferences` API and FAILS at runtime because today's scanner
flags task-doc identifiers and test-class references. Verify with `test`, not
`build-for-testing`.

TDD coverage: `MerlinTests/Unit/DocReferenceGraphScopeTests.swift`.

---

## Write to: MerlinTests/Unit/DocReferenceGraphScopeTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 316a — failing tests for DocReferenceGraph scoping.
final class DocReferenceGraphScopeTests: XCTestCase {

    func testTasksDocsAndTestSymbolsAreNotFlagged() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-scope-\(UUID())", isDirectory: true)
        let tasksDir = dir.appendingPathComponent(" tasks")
        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(
            at: tasksDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A test-target source file declaring a symbol.
        try "final class WidgetSpecHelper {}\n".write(
            to: testsDir.appendingPathComponent("WidgetSpecHelper.swift"),
            atomically: true, encoding: .utf8)
        // A task doc citing an identifier that exists nowhere in the tree.
        try "# Task 1\nUses `BogusTaskOnlyType` here.\n".write(
            to: tasksDir.appendingPathComponent("task-1-demo.md"),
            atomically: true, encoding: .utf8)
        // A product doc: one reference to a real test symbol, one genuinely absent.
        try "# Manual\nSee `WidgetSpecHelper` and `GenuinelyAbsentType`.\n".write(
            to: dir.appendingPathComponent("Manual.md"),
            atomically: true, encoding: .utf8)

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: dir.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "BogusTaskOnlyType" },
                       "identifiers inside tasks/ docs must not be flagged")
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "WidgetSpecHelper" },
                       "a doc reference to a symbol declared in a test file is not stale")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "GenuinelyAbsentType" },
                      "a genuinely absent symbol must still be flagged (control)")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphScopeTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testTasksDocsAndTestSymbolsAreNotFlagged` **FAILS** (the
two `XCTAssertFalse` checks fail against today's scanner). Verified with `test` because
the failure is at runtime.

## Commit
```
git add MerlinTests/Unit/DocReferenceGraphScopeTests.swift tasks/task-316a-doc-reference-scope-tests.md
git commit -m "Task 316a — DocReferenceGraph scope tests (failing)"
```
