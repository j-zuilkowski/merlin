# Task 488 - F5 electronics completion contract status

## Objective

Complete F5 from the finite electronics-domain finish checklist.

This is a documentation/status cleanup task. It must mark the electronics
domain finished only as evidence-gated workflow infrastructure, and must not
claim that AmpDemo or every future electronics request reaches `FAB_READY`
without the required component, catalog, SPICE, BOM, fabrication, and approval
evidence.

## Fail-First Evidence

Focused red test:

```bash
rm -rf /tmp/merlin-derived-task488 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task488 -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testElectronicsFinishChecklistMatchesFinalEvidenceContract
```

Result: `TEST FAILED`, 1 test, 14 failures. The handoff still listed latest
completed task as Task 487 and F5 unchecked, while `plugins/electronics/spec.md`
still described full PCB/fabrication and natural-language-to-fabrication
workflow as outside the first milestone.

## Implementation

- Added a final documentation sweep assertion covering the F5 completion
  contract.
- Updated `plugins/electronics/spec.md` to describe the current full
  evidence-gated workflow path through `FAB_READY` or an honest blocked
  evidence package.
- Removed stale first-milestone language that limited the plugin spec to
  low-voltage schematic verification.
- Updated `plugins/electronics/README.md` with the current bounded status:
  electronics is finished as evidence-gated workflow infrastructure, and the
  current GUI proof stops at `COMPONENT_SELECTION_REVISION_BLOCKED`.
- Updated `tasks/HANDOFF.md` to mark F5 complete and latest completed task as
  Task 488.

## Green Evidence

Focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task488 -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testElectronicsFinishChecklistMatchesFinalEvidenceContract
```

Result: `TEST SUCCEEDED`, 1 test, 0 failures.

Final focused sweep:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task488 -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

`git diff --check` passed.
