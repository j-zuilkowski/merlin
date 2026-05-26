# Task 379a - llama.cpp context-overrun tests

## Context

The live S2 run with the real xcalibre-server backend and one llama.cpp router-mode
local provider pair reached Merlin's execute provider, then failed on llama.cpp HTTP
400:

```text
request (8226 tokens) exceeds the available context size (8192 tokens), try increasing it
type: exceed_context_size_error
n_prompt_tokens: 8226
n_ctx: 8192
```

Merlin already has context-overrun recovery, but the classifier does not cover this
llama.cpp error shape. The numeric limit extractor also must not record the requested
prompt size as the provider's context window.

## Traceability

- Vision reference: vision.md#local-first-provider-routing-and-recovery
- Spec reference: spec.md#llama-cpp-router-provider
- Tests: MerlinTests/Unit/ContextLengthRecoveryTests.swift

## Behavior

WHEN a provider returns HTTP 400 with llama.cpp `exceed_context_size_error` THE SYSTEM SHALL classify it as a context-length overflow.
WHEN a llama.cpp overflow body includes both `n_prompt_tokens` and `n_ctx` THE SYSTEM SHALL record `n_ctx` as the observed context limit.
WHEN a llama.cpp overflow body says "exceeds the available context size" THE SYSTEM SHALL trigger the existing compaction/retry path rather than surfacing a raw HTTP 400.

## Failing Tests

Add tests to `MerlinTests/Unit/ContextLengthRecoveryTests.swift`:

1. `test_isContextLengthExceeded_true_for_llamacpp_available_context_body`
2. `test_observedContextLimit_prefers_llamacpp_nCtx_over_promptTokens`

Expected before implementation:

```text
XCTAssertTrue failed - expected llama.cpp context overflow to classify as context length exceeded
XCTAssertEqual failed - expected n_ctx 8192, not n_prompt_tokens 8226
```

## Verification

```bash
xcodebuild -scheme MerlinTests test \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-task-379a \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/ContextLengthRecoveryTests \
  | grep -E 'Executed.*tests|BUILD|failed'
```

## Commit

```bash
git add tasks/task-379a-llamacpp-context-overrun-tests.md MerlinTests/Unit/ContextLengthRecoveryTests.swift
git commit -m "Task 379a - llama.cpp context overrun tests (failing)"
```
