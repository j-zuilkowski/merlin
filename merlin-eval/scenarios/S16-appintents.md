# S16 — AppIntents / Shortcuts / Siri

Proves Merlin's external-invocation surface — the App Intents exposed to Shortcuts and
Siri. Covers `SURFACE-INVENTORY.md` section Q.

## Mechanism
M4 (invoke the intents via the Shortcuts app / `shortcuts run`) + M2 (observe the effect
in the Merlin UI). Partly manual — Siri invocation is M5.

## What is exercised

`Merlin/Support/AppIntentsSupport.swift` exposes three App Intents — two user-facing
plus a metadata intent:

- **StartMerlinSessionIntent** — invoke it (Shortcuts app, or `shortcuts run`); assert a
  new Merlin session is created and becomes active.
- **SendMerlinPromptIntent(prompt:)** — invoke with a prompt string; assert the prompt is
  delivered to the active session and a response is produced. Invoke with an empty
  prompt; assert the documented validation rejects it.
- **MerlinMetadataIntent** — the app-discovery intent (no-op `perform`); assert it is
  registered so Merlin's actions surface in Shortcuts at all.

Also:
- Assert both intents are discoverable in the macOS Shortcuts app (they appear under
  Merlin's actions).
- Assert invoking `SendMerlinPromptIntent` with no Merlin session/window open behaves
  sanely (launches / creates a session, or fails with a clear message — not a crash).

## Scoring rubric
- [ ] All three App Intents are registered; the two user-facing ones appear in the
      Shortcuts app under Merlin.
- [ ] `StartMerlinSessionIntent` creates and activates a new session.
- [ ] `SendMerlinPromptIntent` delivers the prompt and yields a response.
- [ ] Empty-prompt validation rejects cleanly.
- [ ] Cold-start invocation (no window open) does not crash.

**Score:** checks passed / 6.

## Runsheet
1. Tasks B–D, 301–306 merged; Merlin built and installed.
2. Open the macOS Shortcuts app; confirm Merlin's two actions appear.
3. Build a Shortcut for each intent; run them (also try `shortcuts run` from a terminal).
4. Try a Siri invocation of one intent (manual, M5).
5. Score; write `results/S16-<date>.md`.
