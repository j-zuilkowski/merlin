# Phase 304b — Discipline Chip Count (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 304a complete: failing test in `PendingAttentionChipCountTests`.

The chip showed at most 3 because it read `findings.count` and `findings` is the capped
top-3 panel subset. Give the chip the true total.

## Edit: Merlin/Discipline/DisciplineEngine.swift
Add a count accessor next to `pendingAttention(projectPath:)`:
```swift
/// The full count of queued findings (the chip badge total, uncapped).
func pendingAttentionCount() async -> Int {
    await queue.all().count
}
```

## Edit: Merlin/ViewModels/PendingAttentionViewModel.swift
- Add `@Published var totalCount: Int = 0`.
- In `refresh(projectPath:)`, set it alongside `findings`:
```swift
func refresh(projectPath: String) async {
    findings = Array(await disciplineEngine.pendingAttention(projectPath: projectPath).prefix(3))
    totalCount = await disciplineEngine.pendingAttentionCount()
}
```

## Edit: Merlin/Views/PendingAttentionChipView.swift
Use `totalCount` instead of `findings.count` for the badge number, the help string, and
the visibility:
- `Text("\(viewModel.totalCount)")`
- `.help("Discipline: \(viewModel.totalCount) pending findings")`
- `.opacity(viewModel.totalCount == 0 ? 0 : 1)`

`chipColor` may keep reading `viewModel.findings` (the top-3 already include the most
severe, since the queue sorts by severity).

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/PendingAttentionChipCountTests \
  -only-testing:MerlinTests/PendingAttentionViewModelTests
```
Expected: BUILD SUCCEEDED, all tests pass.

Runtime check: with >3 discipline findings queued, confirm the chip shows the real count
and the panel still lists 3.

## Commit
```
git add Merlin/Discipline/DisciplineEngine.swift Merlin/ViewModels/PendingAttentionViewModel.swift \
  Merlin/Views/PendingAttentionChipView.swift phases/phase-304b-discipline-chip-count.md
git commit -m "Phase 304b — Discipline chip shows true finding count"
```
