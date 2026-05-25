# Task 264a — Discipline UI Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 263b complete: project:adopt SKILL.md installed.

Introduces the pending-attention chip in the chat view and the expandable panel that shows
the top-3 findings with dismiss affordances.

New surface introduced in task 264b:
  - `PendingAttentionChipView` SwiftUI view in `Merlin/Views/PendingAttentionChipView.swift`.
  - `PendingAttentionPanelView` SwiftUI view in `Merlin/Views/PendingAttentionPanelView.swift`.
  - `PendingAttentionViewModel` `@MainActor ObservableObject` in
    `Merlin/ViewModels/PendingAttentionViewModel.swift`:
    `@Published var findings: [Finding]`
    `@Published var isExpanded: Bool`
    `func refresh(projectPath: String) async`
    `func dismiss(finding: Finding, rationale: String) async`
  - The chip shows finding count; tapping expands the panel. Panel shows top-3 findings
    with dismiss button per finding.

TDD coverage:
  File 1 — `MerlinTests/Unit/PendingAttentionViewModelTests.swift`:
    `refresh` populates `findings` from the queue; `dismiss` removes the finding and
    calls the queue; `isExpanded` toggles independently of `findings`; empty queue
    after dismiss leaves `findings` empty.

---

## Write to

- `MerlinTests/Unit/PendingAttentionViewModelTests.swift`

### MerlinTests/Unit/PendingAttentionViewModelTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class PendingAttentionViewModelTests: XCTestCase {

    private func makeTmpQueue() -> (PendingAttentionQueue, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pavm-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("pending.json").path
        return (PendingAttentionQueue(storePath: path), dir)
    }

    private func makeFinding(severity: Severity = .nudge) -> Finding {
        Finding(
            id: UUID(), category: .taskDrift, severity: severity,
            summary: "Test finding", detail: "Detail",
            suggestedAction: "Fix it", createdAt: Date(), lastSeenAt: Date()
        )
    }

    // MARK: - refresh populates findings

    func testRefreshPopulatesFindings() async throws {
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        XCTAssertFalse(vm.findings.isEmpty)
    }

    // MARK: - dismiss removes finding

    func testDismissRemovesFinding() async throws {
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        await vm.dismiss(finding: f, rationale: "not relevant")
        await vm.refresh(projectPath: dir.path)
        XCTAssertTrue(vm.findings.filter { $0.id == f.id }.isEmpty)
    }

    // MARK: - isExpanded toggles independently

    func testIsExpandedTogglesIndependently() {
        let (queue, _) = makeTmpQueue()
        let vm = PendingAttentionViewModel(queue: queue)
        XCTAssertFalse(vm.isExpanded)
        vm.isExpanded = true
        XCTAssertTrue(vm.isExpanded)
        vm.isExpanded = false
        XCTAssertFalse(vm.isExpanded)
    }

    // MARK: - empty queue after dismiss

    func testEmptyQueueAfterLastDismiss() async throws {
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        await vm.dismiss(finding: f, rationale: "done")
        await vm.refresh(projectPath: dir.path)
        XCTAssertTrue(vm.findings.isEmpty)
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
```

Expected: **BUILD FAILED** with errors naming `PendingAttentionViewModel`.

## Commit

```bash
git add tasks/task-264a-discipline-ui-tests.md \
    MerlinTests/Unit/PendingAttentionViewModelTests.swift
git commit -m "Task 264a — DisciplineUITests (failing)"
```
