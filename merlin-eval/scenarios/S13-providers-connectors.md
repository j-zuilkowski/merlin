# S13 — Providers, Keys & Connectors

Proves provider configuration, secure key storage, and every external connector work.
Covers `SURFACE-INVENTORY.md` section N.

## Mechanism
M2 (Settings → Providers / Connectors) + M4 (key storage on disk / Keychain) + M1
(`EvalHarness` to exercise a connector tool through the agent).

## What is exercised

**Providers (N):** for the 11 defined providers — confirm each can be enabled, given a
model, and activated. Confirm a remote provider rejects requests cleanly with no key and
works with one. Confirm a local provider (LM Studio) connects. Confirm the
slot→provider mapping (`[slots]`) routes correctly.

**API keys:** add a key via the `APIKeyEntrySheet`; assert it is written to
`~/.merlin/api-keys.json` with `0600` permissions; assert it is read back; delete it;
assert removal. Confirm keys never appear in logs, telemetry, or memories.

**Connectors:** for each — **GitHub, Slack, Linear, Brave Search, xcalibre-server** —
store the token (Settings → Connectors / Search), assert it lands in the Keychain (or
config for xcalibre-server), then exercise the connector through the agent:
- GitHub — fetch a PR / issue / file.
- Slack — post a message to a test channel.
- Linear — read an issue / project status.
- Brave — run a `web_search`.
- xcalibre-server — a RAG query (overlaps S4 — here just confirm the token wires the client).

Each connector with NO token configured must fail gracefully (clear error, no crash).

## Scoring rubric
- [ ] Each of the 11 providers enables/configures/activates correctly.
- [ ] A remote provider: clean failure without a key, success with one.
- [ ] API keys persist to `~/.merlin/api-keys.json` at `0600`, read back, and delete.
- [ ] Keys/tokens never leak into logs, telemetry, or generated memories.
- [ ] Each of the 5 connectors authenticates and performs one real operation.
- [ ] Each connector degrades gracefully when unconfigured.

**Score:** providers / 11 + connectors / 5 + the key-handling checks.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built. Use test/throwaway tokens where possible.
2. Configure providers and keys via Settings; inspect `~/.merlin/api-keys.json` perms.
3. Configure each connector; run one agent task per connector via `EvalHarness` or manually.
4. Grep logs/telemetry/memories for any token leakage.
5. Score; write `results/S13-<date>.md`.
