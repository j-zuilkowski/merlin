# Task 487 - F4 GUI spec path recovery

## Objective

Fix the fresh full GUI workflow blocker found during F4 evidence collection:
Merlin stopped before DesignIntent because the model called `read_file` for a
nonexistent absolute `spec.md` path outside the active project root instead of
the active project's requirements file.

The fix must be generic for project-scoped requirements/spec reads. It must not
special-case AmpDemo or hand-design any electronics artifact.

## Fail-First Evidence

Fresh GUI run evidence before this fix:

- Merlin was launched from `/Applications/Merlin.app` with
  `--open-project /Users/jonzuilkowski/Documents/localProject/AmpDemo
  --active-domain electronics`.
- The injected F4 workflow prompt was consumed through `~/.merlin/inject.txt`.
- The session stopped at the first requirements-read step after calling:

```json
{"name":"read_file","arguments":"{\"path\":\"/Users/merlin/Documents/spec.md\"}"}
```

- Tool result:

```text
HANDLER_ERROR: Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"
```

Focused red test:

```bash
rm -rf /tmp/merlin-derived-task487 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task487 -only-testing:MerlinTests/ProjectScopedToolTests/testReadFileMissingAbsoluteSpecPathFallsBackToProjectSpec
```

Result: `TEST FAILED`, 1 test, 4 failures. The registered `read_file` handler
returned the same missing-file handler error instead of reading the active
project's `spec.md`.

Additional focused red tests found two more full-GUI evidence path gaps:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task487 -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testRelativeSpecArtifactPathResolvesAgainstWorkspaceRoot -only-testing:MerlinTests/LoopContinuationTests/testRequirementsInspectionIsNotSatisfiedByDirectoryListingAlone
```

Result: `TEST FAILED`, 2 tests, 5 failures. `kicad_build_intent_model` treated
`./spec.md` as process-CWD relative and returned `blocked`, while the workflow
verification path accepted `list_directory` output containing `spec.md` as
requirements inspection evidence.

## Implementation

`BuiltInToolScope.resolvePath` now applies a narrow project-root recovery for
missing absolute requirements/spec paths. If the requested absolute path does
not exist, the filename is one of `spec.md`, `requirements.md`, or
`requirements.txt`, and the active project root contains that same filename, the
tool reads the project-root file and prefixes the output with a correction
warning.

This keeps ordinary absolute paths unchanged, preserves the existing outside
project warning behavior, and avoids AmpDemo-specific routing.

`kicad_build_intent_model` now resolves relative input artifact paths against
the active electronics workspace root. This keeps `./spec.md` grounded in the
current project instead of the process working directory.

Requirements inspection evidence now requires a non-empty `read_file` or
`search_files` result that names a requirements/spec artifact. A directory
listing that merely shows `spec.md` no longer advances the full workflow.

## Green Evidence

Focused commands:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task487 -only-testing:MerlinTests/ProjectScopedToolTests
```

Result: `TEST SUCCEEDED`, 6 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task487 -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testRelativeSpecArtifactPathResolvesAgainstWorkspaceRoot -only-testing:MerlinTests/LoopContinuationTests/testRequirementsInspectionIsNotSatisfiedByDirectoryListingAlone
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Final focused regression command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task487 -only-testing:MerlinTests/ProjectScopedToolTests -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testRelativeSpecArtifactPathResolvesAgainstWorkspaceRoot -only-testing:MerlinTests/LoopContinuationTests/testRequirementsInspectionIsNotSatisfiedByDirectoryListingAlone
```

Result: `TEST SUCCEEDED`, 8 tests, 0 failures.

## GUI Evidence

Fresh F4 rerun used the rebuilt `/Applications/Merlin.app` opened with:

```bash
open -na /Applications/Merlin.app --args --open-project /Users/jonzuilkowski/Documents/localProject/AmpDemo --active-domain electronics
```

The F4 workflow prompt was consumed through `~/.merlin/inject.txt`. The final
session log is:

```text
/Users/jonzuilkowski/Library/Application Support/Merlin/sessions/_Users_jonzuilkowski_Documents_localProject_AmpDemo/8F316606-315D-41F0-B2F4-719BF1CC1C1D.json
```

Evidence screenshots:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/07_clean_session_task487_after_evidence_fixes.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/08_request_injected_task487_after_evidence_fixes.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/09_component_revision_blocked_task487.png
```

The rerun proved that directory listing alone did not satisfy requirements
inspection. The session recorded `[electronics evidence still missing for
current step - rescheduling first unverified step]`, then the model called:

```json
{"name":"read_file","arguments":"{\"path\":\"./spec.md\"}"}
```

Merlin then generated and approved DesignIntent, generated Circuit IR, ran
component selection, and attempted component-selection revision.

Generated artifacts:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/7FAAE25B-810E-4B31-85E0-72797531FEDC-design_intent.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/709D779E-114D-4909-80CD-CA772F62CFC5-design_intent.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/CB790BD0-9366-47AE-9980-1F950467894C-circuit_ir.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/F9548B74-EB64-4144-A971-D414C3B0FD45-component_matrix.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/C16986CC-CD3C-4DC8-ABB2-AB82FF877E50-component_matrix.json
```

The run stopped honestly at:

```text
COMPONENT_SELECTION_REVISION_BLOCKED
```

The stop requested concrete manufacturer, MPN, package, ratings,
datasheet/provenance evidence, and footprint/pin compatibility for unresolved
refdes before assigning footprints. Merlin did not advance to footprint
assignment, schematic, PCB, ERC, DRC, SPICE, BOM/vendor, fabrication/CAM, or
`FAB_READY` from unresolved component evidence.

## Status

F4 is complete as fresh full-GUI workflow evidence: the rebuilt app now reaches
an actionable evidence gate through the real GUI/workflow path and stops there
instead of failing on internal path/context handling or advancing from
placeholders.
