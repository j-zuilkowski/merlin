# Task 496 - Release Local Provider Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#provider-integration

## Behavior

WHEN the v2.4.0 release ledger reaches the local-provider gate THE workflow
SHALL run evidence-scoped local provider pair smokes for the documented reliable
local alternatives that are not covered by the separate llama.cpp router gate.

WHEN a provider must be started by the release gate THE workflow SHALL record
startup evidence, smoke output, and shutdown/port cleanup evidence in the
release log.

WHEN a provider prerequisite is missing THE ledger SHALL record the exact
missing executable, model, or port conflict instead of advancing post-green
screenshots.

## Goal

Run release gate #5 for LM Studio and Jan local-provider pair coverage without
running the full AmpDemo GUI demo or the separate llama.cpp router gate.

## Evidence

- Fail-first: `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.fail-first.log`
  recorded the first gate wrapper attempt incorrectly treating an empty
  `lsof` result as an occupied Jan port before any provider smoke ran.
- Running target: `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.log`.
- Green: `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.log`
  records `GATE 5 PASS`. LM Studio passed text completion, streaming, tool
  calls, and explicit vision request; Jan passed text completion, streaming,
  tool calls, then passed a separate vision lifecycle smoke. Cleanup evidence
  records ports `1234` and `1337` closed.
