# Task 229a - CBR Cover Support Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
The Merlin task archive includes an xcalibre deferred item: CBR/RAR cover extraction returns `Ok(None)` because external `unrar` support was not implemented.

New surface introduced in task 229b:
  - CBR cover extraction via an injectable RAR listing/extraction runner.
  - Unit tests avoid requiring a real `unrar` binary by using a fake runner.

TDD coverage:
  File 1 - `processing/tests/cbr_cover_tests.rs`: first alphabetical image extraction, no-image fallback, missing-runner behavior.

---

## Add: processing/tests/cbr_cover_tests.rs

Create tests that assert:

1. A fake RAR runner with image entries returns the first image alphabetically.
2. Non-image entries and `__MACOSX` entries are ignored.
3. CBR with no image returns `Ok(None)`.
4. Missing `unrar`/runner returns `Ok(None)` with no panic.
5. Extraction errors map to `ProcessingError` without crashing.

Do not require a real RAR fixture or real `unrar` in tests.

---

## Verify

```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test cbr_cover_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```

Expected: **tests fail to compile** because injectable CBR/RAR cover support does not exist.

## Commit

```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/cbr_cover_tests.rs
git commit -m "Task 229a - CBR cover support tests (failing)"
```

