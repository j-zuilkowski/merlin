# Phase 316a — DocReferenceGraph Scope Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 315b complete: `merlin-discipline scan` exists.

The first real `merlin-discipline scan` of the Merlin repo produced 1578
`docStaleReference` findings — ~99% false positives. Two root causes:
  1. `danglingReferences` scans `phases/*.md` — build scaffolding full of historical and
     illustrative identifiers (1130 of the findings cite a `phases/` doc).
  2. `enumerateSourceSymbols` excludes `Tests/`, so a doc that legitimately names a test
     class is reported as a dangling reference to a missing symbol.

Phase 316b fixes both: skip `phases/` entirely in `danglingReferences`, and include test
files in the source-symbol set.

**This is a runtime-failure phase.** The test compiles against the existing
`DocReferenceGraph.danglingReferences` API and FAILS at runtime because today's scanner
flags phase-doc identifiers and test-class references. Verify with `test`, not
`build-for-testing`.

TDD coverage: `MerlinTests/Unit/DocReferenceGraphScopeTests.swift`.

---

## Write to: MerlinTests/Unit/DocReferenceGraphScopeTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 316a — failing tests for DocReferenceGraph scoping.
final class DocReferenceGraphScopeTests: XCTestCase {

    func testPhasesDocsAndTestSymbolsAreNotFlagged() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-scope-\(UUID())", isDirectory: true)
        let phasesDir = dir.appendingPathComponent("phases")
        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(
            at: phasesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A test-target source file declaring a symbol.
        try "final class WidgetSpecHelper {}\n".write(
            to: testsDir.appendingPathComponent("WidgetSpecHelper.swift"),
            atomically: true, encoding: .utf8)
        // A phase doc citing an identifier that exists nowhere in the tree.
        try "# Phase 1\nUses `BogusPhaseOnlyType` here.\n".write(
            to: phasesDir.appendingPathComponent("phase-1-demo.md"),
            atomically: true, encoding: .utf8)
        // A product doc: one reference to a real test symbol, one genuinely absent.
        try "# Manual\nSee `WidgetSpecHelper` and `GenuinelyAbsentType`.\n".write(
            to: dir.appendingPathComponent("Manual.md"),
            atomically: true, encoding: .utf8)

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: dir.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "BogusPhaseOnlyType" },
                       "identifiers inside phases/ docs must not be flagged")
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
Expected: BUILD SUCCEEDED; `testPhasesDocsAndTestSymbolsAreNotFlagged` **FAILS** (the
two `XCTAssertFalse` checks fail against today's scanner). Verified with `test` because
the failure is at runtime.

## Commit
```
git add MerlinTests/Unit/DocReferenceGraphScopeTests.swift phases/phase-316a-doc-reference-scope-tests.md
git commit -m "Phase 316a — DocReferenceGraph scope tests (failing)"
```
