# Task 518 - Release Publication Docs

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN the v2.4.0 release is published THE repository SHALL expose current release
notes, public screenshots, and user/developer documentation links from GitHub's
default branch and release page.

## Objective

Repair the public documentation gaps found after PR #3 merged to `main`:

- add missing top-level release notes for v2.3.0 and v2.4.0
- make README user-facing documentation links clickable
- make the current release notes embed the public screenshot assets
- update the GitHub Release body so screenshots render inline instead of only
  appearing as downloadable assets

## Evidence

Fail-first focused test:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task518 -only-testing:MerlinTests/ReleaseNotes224Tests
```

Result bundle:

`/tmp/merlin-derived-task518/Logs/Test/Test-MerlinTests-2026.06.12_10-18-41--0400.xcresult`

Failures proved missing `RELEASE-v2.3.0.md`, missing `RELEASE-v2.4.0.md`,
missing README links for `UserGuide.md`, `DeveloperManual.md`, and current
release notes, plus missing current release-note screenshot embeds.

## Verification

Focused release-note/documentation tests:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task518 -only-testing:MerlinTests/ReleaseNotes224Tests
```

Passed 5 tests with result bundle:

`/tmp/merlin-derived-task518/Logs/Test/Test-MerlinTests-2026.06.12_10-20-39--0400.xcresult`

Focused SDD traceability scanner:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task518 -only-testing:MerlinTests/SDDTraceabilityScannerTests/testCurrentRepositoryTasksAreBackfilled
```

Passed 1 test with result bundle:

`/tmp/merlin-derived-task518/Logs/Test/Test-MerlinTests-2026.06.12_10-20-39--0400.xcresult`

`git diff --check` passed.

The published GitHub Release `v2.4.0` was updated with inline screenshot
Markdown and direct documentation links:

`https://github.com/j-zuilkowski/merlin/releases/tag/v2.4.0`

Post-push CI run `27421746927` failed in
`FinalElectronicsDocumentationSweepTests.testElectronicsFinishChecklistMatchesFinalEvidenceContract`
because the guard still expected `Latest completed task is Task 517`. The guard
was updated to require Task 518 and the Task 518 handoff paragraph.

Focused CI-failure repair check:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task518 -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testElectronicsFinishChecklistMatchesFinalEvidenceContract
```

Passed 1 test with result bundle:

`/tmp/merlin-derived-task518/Logs/Test/Test-MerlinTests-2026.06.12_10-33-38--0400.xcresult`

Neighbor focused release-note and SDD checks passed 6 tests in the same result
bundle.
