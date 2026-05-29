# Task 404a - Electronics Runtime Artifact Evidence Tests

Goal: prove structured runtime workflow requests can pass verifier artifact paths
instead of prebuilt in-memory evidence.

Add focused tests in `MerlinTests/Unit/ElectronicsRuntimeHarnessIntegrationTests.swift`.

Required assertions:

1. `workflow.requirements_to_pcb` accepts `evidence_artifacts`.
2. The runtime builds `ElectronicsEndToEndEvidence` through
   `ElectronicsEvidenceArtifactAdapter`.
3. Clean verifier artifact paths produce a `FAB_READY` harness result.
4. The request must not require callers to preconstruct `ElectronicsEndToEndEvidence`.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBuildsHarnessEvidenceFromArtifactPaths
```

Expected before task 404b: fail because `ElectronicsEndToEndWorkflowRequest`
requires `evidence`.
