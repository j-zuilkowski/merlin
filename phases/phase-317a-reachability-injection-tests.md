# Phase 317a — ReachabilityScanner Injection-Detection Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 316b complete: `DocReferenceGraph` scoping fixed.

The first real `merlin-discipline scan` produced 2 `unwiredComponent` findings, both
false positives:
  1. `ChatViewModel` — flagged "never injected", but it is injected via
     `.environmentObject(session.chatViewModel)` in three places. The scanner only
     recognises injection when the type is *constructed inline*; injection through a
     property reference (the common case) is missed. The owning `@StateObject` is an
     annotation-only declaration (`@StateObject var x: ChatViewModel`), which the
     scanner also does not read.
  2. `T` — the scanner matched the literal text `@EnvironmentObject var x: T` inside its
     own doc comment.

Phase 317b fixes both: `injectedTypes` also reads `@StateObject` / `@ObservedObject`
type annotations, and the per-line heuristics skip comment lines.

**This is a runtime-failure phase.** The test compiles against the existing
`ReachabilityScanner.scan` API and FAILS at runtime. Verify with `test`.

TDD coverage: `MerlinTests/Unit/ReachabilityScannerInjectionTests.swift`.

---

## Write to: MerlinTests/Unit/ReachabilityScannerInjectionTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 317a — failing tests for ReachabilityScanner injection detection.
final class ReachabilityScannerInjectionTests: XCTestCase {

    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reach-inject-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: dir.appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// A type owned by an annotation-only `@StateObject` (no inline constructor on the
    /// declaration line) and injected by property reference must NOT be flagged.
    func testAnnotationInjectedTypeIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "AppModel.swift": "import SwiftUI\nfinal class AppModel: ObservableObject {}",
            "ConsumerView.swift": """
            import SwiftUI
            struct ConsumerView: View {
                @EnvironmentObject var model: AppModel
                var body: some View { Text("x") }
            }
            """,
            "HostView.swift": """
            import SwiftUI
            struct HostView: View {
                @StateObject private var model: AppModel
                init() { _model = StateObject(wrappedValue: AppModel()) }
                var body: some View { ConsumerView().environmentObject(model) }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.symbol == "AppModel" && $0.kind == "environment-object-not-injected"
        }, "a type owned by an annotation-only @StateObject must not be flagged")
    }

    /// An `@EnvironmentObject` written inside a comment must not register a consumer.
    func testCommentDeclaredEnvObjectIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "RealView.swift": """
            import SwiftUI
            struct RealView: View {
                // Historically this used @EnvironmentObject var ghost: GhostModel
                var body: some View { Text("hi") }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.symbol == "GhostModel" },
                       "an @EnvironmentObject mentioned only in a comment is not a consumer")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/ReachabilityScannerInjectionTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; both tests **FAIL** against today's scanner. Verified with
`test` because the failures are at runtime.

## Commit
```
git add MerlinTests/Unit/ReachabilityScannerInjectionTests.swift phases/phase-317a-reachability-injection-tests.md
git commit -m "Phase 317a — ReachabilityScanner injection-detection tests (failing)"
```
