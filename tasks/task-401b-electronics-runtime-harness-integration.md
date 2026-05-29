# Task 401b - Electronics Runtime Harness Integration

Goal: make runtime electronics workflow status come from
`ElectronicsEndToEndHarness` when structured DesignIntent/CircuitIR evidence is
provided.

Implementation requirements:

1. Add a runtime workflow request shape for:
   - `job_id`
   - `design_intent_path`
   - `circuit_ir_path`
   - `output_directory`
   - `evidence`
   - optional `approvals`
2. In `ElectronicsRuntimePlugin`, route structured workflow requests through
   `ElectronicsEndToEndHarness`.
3. Return `WorkspaceMessageResponse.status == .blocked` only when the harness
   result is `BLOCKED`; return `.ok` for `SCHEMATIC_VERIFIED`, `PCB_VERIFIED`,
   `FAB_READY`, and `COMPLETE`.
4. Encode `ElectronicsEndToEndResult` in the payload so the UI/agent sees the
   same evidence-gated status that the backend used.
5. Do not infer completion from chat text, plan steps, or legacy final-report
   strings.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests
```

Expected after task 401b: tests pass.
