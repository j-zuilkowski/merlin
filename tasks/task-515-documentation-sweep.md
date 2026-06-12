# Task 515 - Documentation Sweep

## Objective

Run a focused documentation sweep after the local `v2.4.0` tag was created.
Cross-check code comments, Developer Manual references, user-facing manual
coverage, and release evidence status against `spec.md`.

## Spec Rules Applied

- User-facing surfaces must be covered by the user manual.
- Code comments should stay sparse and explain non-obvious intent.
- Developer Manual source-comment cross references must point to real sections.
- The Developer Manual Code Map must include source-commented files.
- Release evidence must reflect the latest completed gate honestly.

## Fail-First Evidence

Focused red runs were captured with:

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived-task515 \
  -only-testing:MerlinTests/DocumentationSweepTests/testDeveloperManualCodeMapCoversSourceCommentCrossReferences
```

and:

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived-task515 \
  -only-testing:MerlinTests/DocumentationSweepTests/testUserGuideTableOfContentsCoversCurrentUserFacingSections \
  -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testReleaseEvidenceReportSummarizesPassedGatesAndBoundaries
```

The failures proved:

- `App/MerlinCommands.swift` was missing from the Developer Manual Code Map.
- `Sessions/WorkspaceCoordinator.swift` was missing from the Developer Manual
  Code Map.
- `ContextManager.swift` referenced a stale manual section name.
- The User Guide table of contents omitted the current Electronics and
  Behavioral Reliability user-facing sections.
- The release report still summarized status only through gate #12 after gate
  #14 had completed locally.

## Changes

- Added focused documentation-sweep tests for source-comment Developer Manual
  cross references and User Guide table-of-contents coverage.
- Updated `ContextManager.swift` to reference the current Developer Manual
  section name.
- Added `WorkspaceCoordinator` to the Developer Manual and refreshed Code Map
  entries for `WorkspaceCoordinator` and `MerlinCommands`.
- Updated the User Guide table of contents to include Electronics and
  Behavioral Reliability.
- Updated the release evidence report summary through gate #14.

## Tag Note

This task changes release files after Task 514 created the initial local
`v2.4.0` tag. Before gate #15 pushes the tag, the local tag must point at the
final release commit that includes this sweep.
