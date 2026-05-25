# S17 — Notifications

Proves Merlin's system-notification surface. Covers `SURFACE-INVENTORY.md` section R.

## Mechanism
M2 (observe the macOS notification) + M1 (`EvalHarness` to drive the triggering events) +
M5 (manual confirmation of the delivered notification).

## What is exercised

`Merlin/Notifications/NotificationEngine.swift` posts two notifications:

- **"Task complete"** — fired when an agent turn finishes. Drive a session to completion;
  assert a notification is delivered with the session label in the body.
- **"Approval needed"** — fired when a tool needs permission. Drive a task that triggers
  a tool-permission request; assert a notification is delivered naming the tool.

Also:
- First-run permission: on a machine where notification permission was never granted,
  assert macOS prompts for it and that denial degrades gracefully (no crash — the engine
  guards on `isNotificationEnvironmentAvailable`).
- The General settings "Show notifications" toggle: with it off, assert no notifications
  fire; with it on, assert they do.

## Scoring rubric
- [ ] "Task complete" fires on turn completion, body includes the session label.
- [ ] "Approval needed" fires on a tool-permission request, body names the tool.
- [ ] First-run notification permission prompt appears; denial degrades gracefully.
- [ ] The "Show notifications" setting gates delivery.
- [ ] No notification fires in a test/headless environment (the env guard holds).

**Score:** checks passed / 5.

## Runsheet
1. Tasks B–D, 301–306 merged; Merlin built and installed.
2. Reset notification permission (`tccutil reset` or a fresh user) to test the prompt.
3. Drive a turn to completion and a tool-permission request via `EvalHarness` or manually;
   watch the macOS Notification Center.
4. Toggle "Show notifications" off/on and re-check.
5. Score; write `results/S17-<date>.md`.
