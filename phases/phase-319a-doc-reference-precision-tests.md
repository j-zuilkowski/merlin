# Phase 319a — DocReferenceGraph Precision Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 318b complete: scanner tuning 316–318 landed.

The re-scan after 316–318 cut findings 1798 → 648, but `docStaleReference` was still 432.
Two remaining causes:
  1. The scanners walk the `build/` output directory — `DeveloperManual.md` is bundled
     into every `.app`, so each finding is counted 3–4× (there is even a nested
     `Merlin.app/Merlin.app`).
  2. The loose backticked-identifier dangling check flags any `` `PascalCaseWord` `` not
     in Merlin source — including legitimate mentions of Apple/standard-library types
     (`AppKit`, `AsyncThrowingStream`). It runs ~95% false positive.

Phase 319b fixes both: all scanner file enumeration skips `build/` / `DerivedData/` /
`.build/`, and `danglingReferences` drops the loose check, keeping only the
high-precision fenced-block enum-case check (the one that catches the real
`versionBumpCandidate` class).

**This is a runtime-failure phase.** The tests compile against the existing
`DocReferenceGraph.danglingReferences` API and FAIL at runtime. Verify with `test`.

TDD coverage: `MerlinTests/Unit/DocReferenceGraphPrecisionTests.swift`.

---

## Write to: MerlinTests/Unit/DocReferenceGraphPrecisionTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 319a — failing tests for DocReferenceGraph precision.
final class DocReferenceGraphPrecisionTests: XCTestCase {

    /// Writes `[relativePath: content]`, creating intermediate directories.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-319-\(UUID())", isDirectory: true)
        for (rel, content) in files {
            let fileURL = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testLooseBacktickedReferenceIsNoLongerFlagged() async throws {
        let proj = try makeTmpProject([
            "Manual.md": """
            # Manual
            Prose mentioning `LooseDanglingIdentifier` here.

            ```swift
            enum Channel {
                case ghostFencedCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "LooseDanglingIdentifier" },
                       "the loose backticked-identifier check is dropped in phase 319")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostFencedCase" },
                      "the high-precision fenced-block enum-case check is retained")
    }

    func testBuildOutputDocsAreSkipped() async throws {
        let proj = try makeTmpProject([
            "build/Debug/Merlin.app/Contents/Resources/Manual.md": """
            # Bundled Manual
            ```swift
            enum Channel {
                case buildGhostCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "buildGhostCase" },
                       "documents inside build/ output must not be scanned")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphPrecisionTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; both tests **FAIL** against today's scanner. Verified with
`test` because the failures are at runtime.

## Commit
```
git add MerlinTests/Unit/DocReferenceGraphPrecisionTests.swift phases/phase-319a-doc-reference-precision-tests.md
git commit -m "Phase 319a — DocReferenceGraph precision tests (failing)"
```
