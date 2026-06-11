# Task 506 — Capture README and GitHub Feature Screenshots

## Objective

Pass release gate #11 by capturing durable Merlin feature screenshots for the
README/GitHub release path and linking the public README assets to the current
v2.4.0 release evidence.

## Evidence

- Fail-first documentation guard:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.fail-first.log`
- Focused green documentation guard:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.focused-green.log`
- Screenshot capture and cleanup log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.log`
- Public README/GitHub assets:
  `docs/assets/screenshots/v2.4.0/`
- Full-size release evidence captures:
  `docs/e2e/2026-06-08-v2.4.0-release/screenshots/readme/`

## Result

Gate #11 is passed. The README now links the current Merlin workspace,
providers, provider-slot routing, and KiCad generated-file screenshots from
`docs/assets/screenshots/v2.4.0/`. The release evidence keeps full-size Merlin
GUI captures and a gate-owned log with image dimensions and process cleanup.
