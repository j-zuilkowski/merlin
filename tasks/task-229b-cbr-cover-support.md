# Phase 229b - CBR Cover Support

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 229a complete: failing CBR cover tests exist.

---

## Edit: processing/src/cover/cbz.rs

Replace the `ext == "cbr" { return Ok(None) }` placeholder with CBR support through an injectable runner.

Rules:

1. Production runner may shell out to `unrar` if present.
2. Missing `unrar` returns `Ok(None)` so CBR cover extraction remains optional.
3. Tests use a fake runner and do not require external binaries.
4. Entry selection matches CBZ: first image alphabetically, ignoring metadata entries.
5. No new third-party Rust crates unless already present in the workspace.

---

## Verify

```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test cbr_cover_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```

Expected: all CBR cover tests pass and clippy reports no errors.

## Commit

```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/cover/cbz.rs processing/tests/cbr_cover_tests.rs
git commit -m "Phase 229b - CBR cover extraction via unrar runner"
```

