# Task 497 - Release llama.cpp Router Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#llama-cpp-router-provider

## Behavior

WHEN the v2.4.0 release ledger reaches the llama.cpp router gate THE workflow
SHALL start the router-mode `llama-server` with the documented text and vision
model preset and run the local-provider smoke using explicit non-`default`
model IDs.

WHEN the router catalog does not expose the explicit text and vision model IDs
THE gate SHALL fail with the catalog evidence instead of selecting `default`.

WHEN the gate owns the router process THE workflow SHALL stop it and record
port `8081` cleanup evidence before advancing.

## Goal

Run release gate #6 without running the full AmpDemo GUI demo or later screenshot
gates.

## Evidence

- Running target: `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router.log`.
- Green: `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router.log`
  records `GATE 6 PASS`. The router catalog exposed `default` first, but the
  smoke selected explicit `qwen3-coder-local` and `qwen3-vl-local` IDs.
  Completion, streaming, tool-call, and vision checks passed. Cleanup evidence
  records port `8081` closed. Server log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router-server.log`.
