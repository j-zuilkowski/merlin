# Task 389a - Live runner cleanup tests

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#full-green-e2e-battery-v24
- Prior failure: the full live runner required manual cleanup after hanging, temporary configs were restored manually, and evidence directories retained generated logs/backups after screenshots were removed.

## Behavior

WHEN the full live battery finishes, fails, or is interrupted THE runner SHALL stop every provider/xcalibre service it started and restore Merlin config/provider files automatically.
WHEN evidence is collected before the full battery is green THE runner SHALL omit GitHub screenshots, secrets, temporary databases, and config backups from retained artifacts.
WHEN cleanup cannot complete THE runner SHALL fail with the process IDs, paths, and restoration actions that still need attention.

## Red Tests

- Add shell or Swift harness tests that simulate normal exit, test failure, timeout, and interrupt paths and assert cleanup handlers run in each path.
- Assert provider PIDs started by the runner are terminated and not confused with pre-existing user processes.
- Assert config/provider backups are restored and removed from retained evidence artifacts.
- Assert screenshot directories are not retained while the full green gate is red.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullBatteryCleanupTests test
```

Expected red state: cleanup tests fail because the current live runner can require manual kill/restoration and can retain disposable evidence.
