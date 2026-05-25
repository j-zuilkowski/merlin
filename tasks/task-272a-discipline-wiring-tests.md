# Task 272a — Discipline App Integration Wiring Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 271b complete: process and git-hook safety hardened.

**Bug (Critical — v2.2 is dead code).** Nothing in the running app uses the discipline
subsystem. `DisciplineEngine` is never instantiated; the chip/panel views are never
placed in any scene; `HookEngine.runSessionStart` is never called; seed adapters are
never installed at launch; no Stop hook runs `scan()`. The entire v2.2 subsystem ships
but never executes.

Integration anchors (already in the codebase):
  - `Merlin/App/AppState.swift` — `@MainActor final class AppState: ObservableObject`,
    has `let projectPath: String`, builds `engine` in `init`, and already stores a
    Combine sink on `engine.$isRunning.filter { !$0 }` in `cancellables`.
  - `Merlin/Views/ChatView.swift` — the chat UI; its `header` is the natural host for
    the chip + panel.
  - `Merlin/Hooks/HookEngine.swift` — has `static let shared` and
    `func runSessionStart(projectPath:) async -> String?`.

New surface introduced in task 272b:
  - `AppState` stored properties: a `DisciplineEngine` and a
    `@Published var pendingAttention: PendingAttentionViewModel`, both built in `init`.
  - `AppState.init` installs + loads seed adapters and, on session start, calls
    `HookEngine.shared.runSessionStart(projectPath:)`, surfacing the returned note.
  - The post-turn `engine.$isRunning` sink kicks a discipline scan + queue refresh.
  - `ChatView` embeds `PendingAttentionChipView` (which expands `PendingAttentionPanelView`)
    bound to `appState.pendingAttention`.

TDD coverage:
  File 1 — `DisciplineWiringTests.swift`:
    - An `AppState` constructed with a temp `projectPath` exposes a non-nil discipline
      engine and a non-nil `pendingAttention` view-model after `init`.
    - `HookEngine.shared.runSessionStart(projectPath:)` returns a non-nil note string
      when a `pending.json` with findings exists at `<projectPath>/.merlin/pending.json`.
    - A source-presence check: `ChatView.swift` references `PendingAttentionChipView`.

NOTE on expected outcome: the discipline-engine / `pendingAttention` assertions
reference properties that do not exist on `AppState` yet, so this test file may cause a
**BUILD FAILED** rather than a runtime failure. Task 272b must satisfy whichever
occurs. See `## Verify` below.

---

## Write to: MerlinTests/Unit/DisciplineWiringTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class DisciplineWiringTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    // MARK: - AppState wires the discipline subsystem

    func testAppStateExposesDisciplineSubsystem() {
        let appState = AppState(projectPath: projectRoot.path)

        XCTAssertNotNil(appState.disciplineEngine,
            "AppState must build a DisciplineEngine in init")
        XCTAssertNotNil(appState.pendingAttention,
            "AppState must build a PendingAttentionViewModel in init")
    }

    // MARK: - SessionStart hook surfaces findings

    func testSessionStartHookReturnsNoteWhenFindingsExist() async throws {
        // Seed a pending.json with one finding at the project's .merlin path.
        let merlinDir = projectRoot.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(
            at: merlinDir, withIntermediateDirectories: true)

        let finding = Finding(
            id: UUID(),
            category: .taskDrift,
            severity: .block,
            summary: "Missing surface Foo",
            detail: "detail",
            suggestedAction: "Restore Foo",
            createdAt: Date(),
            lastSeenAt: Date()
        )
        let data = try JSONEncoder().encode([finding])
        try data.write(to: merlinDir.appendingPathComponent("pending.json"))

        let note = await HookEngine.shared.runSessionStart(
            projectPath: projectRoot.path)

        XCTAssertNotNil(note,
            "runSessionStart must return a note when pending.json has findings")
        XCTAssertEqual(note?.contains("Missing surface Foo"), true)
    }

    // MARK: - ChatView hosts the chip

    func testChatViewReferencesPendingAttentionChip() throws {
        // Source-presence check: the chip view must be wired into ChatView.
        let chatViewPath = Self.repoRoot()
            .appendingPathComponent("Merlin/Views/ChatView.swift")
        let source = try String(contentsOf: chatViewPath, encoding: .utf8)
        XCTAssertTrue(source.contains("PendingAttentionChipView"),
            "ChatView must embed PendingAttentionChipView")
    }

    /// Walks up from this test file to the repository root.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: either **BUILD FAILED** (because `appState.disciplineEngine` /
`appState.pendingAttention` are referenced before task 272b adds them) OR **BUILD
SUCCEEDED** with `DisciplineWiringTests` failing at runtime (if a partial wiring already
compiles). Both are acceptable for the `a` task — task 272b must make the build
succeed AND all three tests pass.

## Commit

```bash
git add tasks/task-272a-discipline-wiring-tests.md \
    MerlinTests/Unit/DisciplineWiringTests.swift
git commit -m "Task 272a — DisciplineWiringTests (failing)"
```
