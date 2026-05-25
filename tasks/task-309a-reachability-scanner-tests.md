# Phase 309a — ReachabilityScanner Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 308b complete: `StubMarkerScanner` wired into `DisciplineEngine`.

Liveness Discipline batch, unit 3 of 6. `ReachabilityScanner` catches *unwired
components* — code that compiles green but is never reached. Two heuristic checks:

  1. **view-never-instantiated** — a `struct`/`class` conforming to `View` whose name is
     referenced by no other non-test source. Would have caught `RAGSourcesView` and
     `PendingAttentionPanelView` (placed in no view hierarchy).
  2. **environment-object-not-injected** — a type consumed via `@EnvironmentObject`
     whose name is never created/injected anywhere (no `.environmentObject(...)` site,
     no `@StateObject = T(...)`). A guaranteed runtime crash — the bug class that opened
     this whole session.

Both are heuristics surfaced as `nudge` findings for human triage, not blocking gates.

New surface introduced in phase 309b:
  - `UnwiredComponentFinding` — `symbol: String`, `file: String`, `kind: String`,
    `detail: String`.
  - `actor ReachabilityScanner` with `scan(projectPath:) async -> [UnwiredComponentFinding]`.
  - `FindingCategory.unwiredComponent` case.
  - `DisciplineEngine` wiring (defaulted `reachabilityScanner` parameter + conversion).

TDD coverage:
  `MerlinTests/Unit/ReachabilityScannerTests.swift`.

---

## Write to: MerlinTests/Unit/ReachabilityScannerTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 309a — failing tests for ReachabilityScanner.
final class ReachabilityScannerTests: XCTestCase {

    /// Writes `[filename: content]` into a fresh temp project directory.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reachscan-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: dir.appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testDeadViewAndUninjectedEnvObjectAreFlagged() async throws {
        let proj = try makeTmpProject([
            "DeadView.swift": """
            import SwiftUI
            struct DeadView: View {
                var body: some View { Text("never shown") }
            }
            """,
            "ScreenView.swift": """
            import SwiftUI
            struct ScreenView: View {
                @EnvironmentObject var model: GhostModel
                var body: some View { Text("screen") }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains {
            $0.symbol == "DeadView" && $0.kind == "view-never-instantiated"
        }, "a View referenced by no other source must be flagged")
        XCTAssertTrue(findings.contains {
            $0.symbol == "GhostModel" && $0.kind == "environment-object-not-injected"
        }, "an @EnvironmentObject type that is never injected must be flagged")
    }

    func testInjectedEnvironmentObjectIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "ChatModel.swift": "import SwiftUI\nfinal class ChatModel: ObservableObject {}",
            "ConsumerView.swift": """
            import SwiftUI
            struct ConsumerView: View {
                @EnvironmentObject var model: ChatModel
                var body: some View { Text("x") }
            }
            """,
            "RootView.swift": """
            import SwiftUI
            struct RootView: View {
                @StateObject private var model = ChatModel()
                var body: some View { ConsumerView().environmentObject(model) }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.symbol == "ChatModel" && $0.kind == "environment-object-not-injected"
        }, "a type created as a @StateObject and injected must NOT be flagged")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: **BUILD FAILED** — `ReachabilityScanner` / `UnwiredComponentFinding` do not
exist yet.

## Commit
```
git add MerlinTests/Unit/ReachabilityScannerTests.swift tasks/task-309a-reachability-scanner-tests.md
git commit -m "Phase 309a — ReachabilityScanner tests (failing)"
```
