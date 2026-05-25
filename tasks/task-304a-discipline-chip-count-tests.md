# Phase 304a — Discipline Chip Count Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

`PendingAttentionViewModel.refresh` does `findings = Array(... .prefix(3))`, and
`PendingAttentionChipView` shows `viewModel.findings.count` — so the discipline chip
caps its number at 3 even when more findings are queued. The chip should show the TRUE
total; the panel may still list only the top 3.

New surface in phase 304b:
  - `DisciplineEngine.pendingAttentionCount()` — the full queued-finding count.
  - `PendingAttentionViewModel.totalCount: Int` — published; the true total, set by
    `refresh` alongside the (still top-3) `findings`.

TDD coverage:
  `MerlinTests/Unit/PendingAttentionChipCountTests.swift` — with 5 findings queued,
  `refresh` leaves `findings.count == 3` (panel subset) but `totalCount == 5` (chip).

## Write to: MerlinTests/Unit/PendingAttentionChipCountTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 304a — failing test: the discipline chip count must reflect the true number of
/// queued findings, not the capped top-3 panel subset.
final class PendingAttentionChipCountTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacc-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(storePath: String) -> DisciplineEngine {
        DisciplineEngine(
            adapter: .makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: storePath)
    }

    private func makeFinding(_ n: Int) -> Finding {
        Finding(id: UUID(), category: .phaseDrift, severity: .nudge,
                summary: "Finding-\(n)", detail: "d", suggestedAction: "fix",
                createdAt: Date(), lastSeenAt: Date())
    }

    @MainActor
    func testChipCountReflectsTrueTotalNotCappedAtThree() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }

        // Pre-seed the queue's store with 5 distinct findings.
        let pendingURL = project.appendingPathComponent(".merlin/pending.json")
        try FileManager.default.createDirectory(
            at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let seeded = (0..<5).map { makeFinding($0) }
        try JSONEncoder().encode(seeded).write(to: pendingURL)

        let engine = makeEngine(storePath: pendingURL.path)
        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: project.path)

        XCTAssertEqual(vm.findings.count, 3, "the panel subset stays capped at 3")
        XCTAssertEqual(vm.totalCount, 5, "the chip count must be the true queued total")
    }
}
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `PendingAttentionViewModel.totalCount` does not exist.

## Commit
```
git add MerlinTests/Unit/PendingAttentionChipCountTests.swift tasks/task-304a-discipline-chip-count-tests.md
git commit -m "Phase 304a — Discipline chip count tests (failing)"
```
