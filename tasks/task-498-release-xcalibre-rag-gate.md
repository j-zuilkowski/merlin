# Task 498 - Release xcalibre RAG Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#rag-and-xcalibre-integration

## Behavior

WHEN the v2.4.0 release ledger reaches the xcalibre RAG gate THE workflow
SHALL build and start the real sibling `xcalibre-server` backend, authenticate
against it, insert a sentinel Merlin memory chunk, retrieve that sentinel
through the authenticated chunk-search endpoint, delete the sentinel, and stop
the server.

WHEN health, authentication, insert, search, delete, or cleanup fails THE gate
SHALL remain failed with the exact HTTP or process evidence in the release log.

WHEN the gate owns the xcalibre process THE workflow SHALL stop it and record
port `8083` cleanup evidence before advancing.

## Goal

Run release gate #7 without running the full AmpDemo GUI demo or the later
capability convergence gates.

## Evidence

- Fail-first: `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.fail-first.log`
  recorded xcalibre startup failing before health because the release config
  used a non-base64 `jwt_secret`; cleanup confirmed port `8083` closed.
- Running target: `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.log`.
- Green: `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.log`
  records `GATE 7 PASS`. The sibling backend built, started on `127.0.0.1:8083`,
  passed health/openapi checks, authenticated without logging the JWT, inserted
  a sentinel memory chunk, retrieved `TANGERINE-498` from
  `/api/v1/search/chunks`, deleted the sentinel, verified it was absent after
  deletion, and closed port `8083`. Server log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-server.log`.
