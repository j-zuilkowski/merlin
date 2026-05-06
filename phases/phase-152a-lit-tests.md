# Phase 152a — LIT: OPF Metadata Extraction Tests

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Current state: LIT metadata uses `recover_title()` fallback. No OPF metadata extraction from the LIT container exists.

## Problem

LIT files (Microsoft Reader) embed an OPF metadata section at the `/meta` entry of the LIT container. The OPF block uses a binary-tagged format that is readable without LZX decompression. The current stub only scans raw bytes for readable strings — it cannot access the structured title and author fields that are already present in the container. No new crate dependency is needed.

## New surface introduced in phase 152b

- `metadata/lit.rs`: scan LIT file for the `/meta` container entry → parse the OPF binary-tagged format → extract title and author directly from the OPF structure

## TDD coverage

File — `processing/tests/lit_metadata_tests.rs`:

- `test_lit_extracts_title_from_opf_meta` — fixture LIT with OPF metadata block containing title "LIT Test Book" → metadata title is "LIT Test Book"
- `test_lit_extracts_author_from_opf` — fixture LIT with OPF author "Mark Author" → metadata authors contains "Mark Author"
- `test_lit_falls_back_to_recover_title_when_no_meta_entry` — fixture LIT with valid ITOLITLS header but no `/meta` entry → falls back to `recover_title()` producing a non-None title from filename stem
- `test_lit_text_unchanged` — fixture LIT → text extraction via `recover_readable_text()` still works (no regression)

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- lit_metadata 2>&1 | tail -10
# Expected: compilation errors — new LIT metadata parser not yet implemented (phase 152b will fix)
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/lit_metadata_tests.rs
git commit -m "Phase 152a — LIT OPF metadata tests (failing)"
```
