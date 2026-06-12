# Task 404b - Electronics Runtime Artifact Evidence

Goal: wire `ElectronicsEvidenceArtifactAdapter` into structured runtime workflow
requests.

Implementation requirements:

1. Make `ElectronicsEndToEndWorkflowRequest` accept either `evidence` or
   `evidence_artifacts`.
2. If `evidence` is absent and `evidence_artifacts` is present, build evidence
   with `ElectronicsEvidenceArtifactAdapter`.
3. Keep the existing in-memory evidence request path working.
4. Return a blocked structured response if neither evidence form is present.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests/testRequirementsWorkflowBuildsHarnessEvidenceFromArtifactPaths \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests
```

Expected after task 404b: tests pass.
