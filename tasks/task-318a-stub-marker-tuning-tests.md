# Task 318a — StubMarkerScanner Tuning Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Task 317b complete: `ReachabilityScanner` injection detection fixed.

The first real `merlin-discipline scan` produced 4 `stubbedImplementation` findings; 2
are false positives:
  1. `Button("Cancel", role: .cancel) {}` — an empty-bodied `.cancel`-role button is
     idiomatic SwiftUI (the dialog dismisses itself); it is not a stub.
  2. A `TODO` inside a `"""` multi-line string (template content the code emits) — the
     scanner's `isInsideStringLiteral` only understands single-line `"..."` strings.

Task 318b fixes both: skip empty `.cancel`-role buttons, and track `"""` multi-line
string fences so markers inside them are treated as content.

**This is a runtime-failure task.** The tests compile against the existing
`StubMarkerScanner.scan` API and FAIL at runtime. Verify with `test`.

TDD coverage: `MerlinTests/Unit/StubMarkerScannerTuningTests.swift`.

---

## Write to: MerlinTests/Unit/StubMarkerScannerTuningTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 318a — failing tests for StubMarkerScanner tuning.
final class StubMarkerScannerTuningTests: XCTestCase {

    private func makeTmpProject(file: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubtune-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent(file),
                          atomically: true, encoding: .utf8)
        return dir
    }

    func testCancelRoleButtonIsNotFlagged() async throws {
        let proj = try makeTmpProject(file: "Buttons.swift", content: """
        import SwiftUI
        struct V: View {
            var body: some View {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything") {}
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.marker == "empty Button action" && $0.context.contains(".cancel")
        }, "an empty .cancel-role button is idiomatic SwiftUI, not a stub")
        XCTAssertTrue(findings.contains {
            $0.marker == "empty Button action" && $0.context.contains("Delete Everything")
        }, "a non-cancel empty Button action must still be flagged (control)")
    }

    func testMarkerInsideMultilineStringIsNotFlagged() async throws {
        let proj = try makeTmpProject(file: "Template.swift", content: #"""
        import Foundation
        enum Tmpl {
            // TODO: this real marker must still be flagged
            static let body = """
            Section heading
            TODO: replace this section
            """
        }
        """#)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.marker == "TODO" && $0.context.contains("replace this section")
        }, "a TODO inside a multi-line string literal is content, not a code marker")
        XCTAssertTrue(findings.contains {
            $0.marker == "TODO" && $0.context.contains("real marker")
        }, "a genuine TODO comment must still be flagged (control)")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/StubMarkerScannerTuningTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; both tests **FAIL** against today's scanner. Verified with
`test` because the failures are at runtime.

## Commit
```
git add MerlinTests/Unit/StubMarkerScannerTuningTests.swift tasks/task-318a-stub-marker-tuning-tests.md
git commit -m "Task 318a — StubMarkerScanner tuning tests (failing)"
```
