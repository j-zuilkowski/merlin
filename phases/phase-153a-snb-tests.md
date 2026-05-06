# Phase 153a — SNB: SNBF Container Parsing Tests

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Current state: SNB metadata uses only `path.file_stem()` with `_`/`-` replaced by spaces. No SNBF binary container parsing exists.

## Problem

SNB (Shanda Bambook) is a proprietary Chinese ebook format. The SNBF binary container format has documented section headers and a file table pointing to a `book.snbf` metadata XML file containing title, author, publisher, language, and cover information. The current stub ignores all of this — it returns the filename as the title and recovers text heuristically. Plan calls for parsing the SNBF section headers, locating `book.snbf`, and extracting metadata via XML parse. No new crate dependency is needed.

## New surface introduced in phase 153b

- `metadata/snb.rs`: parse SNBF container (section headers → file table → locate `book.snbf`) → parse metadata XML → extract title, author, publisher, language

## TDD coverage

File — `processing/tests/snb_metadata_tests.rs`:

- `test_snb_extracts_title_from_book_snbf` — fixture SNB with `book.snbf` XML containing `<title>南山南</title>` → metadata title is "南山南"
- `test_snb_extracts_author_from_book_snbf` — fixture SNB with `book.snbf` XML containing `<author>张三</author>` → metadata authors contains "张三"
- `test_snb_extracts_publisher` — fixture SNB with `book.snbf` XML containing `<publisher>盛大文学</publisher>` → metadata publisher is "盛大文学"
- `test_snb_falls_back_to_filename_when_no_book_snbf` — fixture SNB with valid SNBP header but no `book.snbf` entry → falls back to filename stem with `_`/`-` replaced by spaces
- `test_snb_text_unchanged` — fixture SNB → text extraction via `recover_readable_text()` still works (no regression)

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- snb_metadata 2>&1 | tail -10
# Expected: compilation errors — new SNB metadata parser not yet implemented (phase 153b will fix)
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/snb_metadata_tests.rs
git commit -m "Phase 153a — SNB SNBF metadata tests (failing)"
```
