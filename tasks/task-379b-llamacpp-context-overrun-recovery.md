# Task 379b - llama.cpp context-overrun recovery

## Context

Task 379a proves that llama.cpp router-mode overflow bodies are not fully covered by
Merlin's context recovery logic. This task makes that provider-specific error shape
first-class while preserving the existing bounded retry and compaction behavior.

## Traceability

- Vision reference: vision.md#local-first-provider-routing-and-recovery
- Spec reference: spec.md#llama-cpp-router-provider
- Tests: tasks/task-379a-llamacpp-context-overrun-tests.md

## Behavior

WHEN llama.cpp returns `exceed_context_size_error` THE SYSTEM SHALL treat the error as a context-length overflow.
WHEN an overflow body exposes an explicit context-window field such as `n_ctx` THE SYSTEM SHALL prefer that field over prompt-size fields when learning the observed provider limit.
WHEN the live router preset is used for GUI/E2E validation THE SYSTEM SHALL run the execute and vision local pair with enough context for capability scenarios instead of an artificially small 8K window.

## Implementation

1. Extend `ProviderError.isContextLengthExceeded` for llama.cpp phrases and error type:
   - `exceed_context_size_error`
   - `exceeds the available context size`
2. Extend `ProviderError.observedContextLimit` to prefer structured `n_ctx` or context-limit phrases before falling back to broad numeric extraction.
3. Raise the live llama.cpp router preset context to `32768` for both local models and align the live script's temporary Merlin `max_tokens` value.

## Verification

```bash
xcodebuild -scheme MerlinTests test \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-task-379b \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/ContextLengthRecoveryTests \
  | grep -E 'Executed.*tests|BUILD|failed'
```

Then rerun the live S2 script:

```bash
RUN_DIR="/Users/jonzuilkowski/Documents/localProject/merlin/docs/e2e/2026-05-26-merlin-full-gui/rerun-live-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN_DIR/logs"
/Users/jonzuilkowski/Documents/localProject/merlin/docs/e2e/2026-05-26-merlin-full-gui/rerun-live-20260526T151224Z/run-live.sh "$RUN_DIR"
```

## Commit

```bash
git add tasks/task-379b-llamacpp-context-overrun-recovery.md Merlin/Providers/ProviderError.swift docs/e2e/2026-05-26-merlin-full-gui/llamacpp-router-models.ini docs/e2e/2026-05-26-merlin-full-gui/rerun-live-20260526T151224Z/run-live.sh
git commit -m "Task 379b - llama.cpp context overrun recovery"
```
