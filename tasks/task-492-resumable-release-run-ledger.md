# Task 492: resumable v2.4.0 release run ledger

## Goal

Prevent release-push work from collapsing back into rolling conversational
checklists. The v2.4.0 release attempt must have a single resumable ledger that
records every required gate, its state, its evidence path, and the next repair
when a gate fails.

## Fail-First Evidence

Focused fail-first command:

```bash
rm -rf /tmp/merlin-derived-task492-red && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task492-red -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testReleaseRunLedgerIsResumableAndBlocksScreenshotsUntilGreen
```

Result: `TEST FAILED` because
`docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md` did not exist.

## Completed Changes

- Added `RELEASE-RUN.md` as the fixed v2.4.0 release state ledger.
- Recorded all full green E2E battery gates, post-green screenshot gates, final
  safety checks, tag, push, and GitHub Release steps.
- Marked the known focused visual contrast failure as the current blocker.
- Marked KiCad and GitHub screenshots as blocked until the full battery is
  green.
- Updated the documentation sweep test so the ledger is required and the handoff
  expectation tracks the current completed task.

