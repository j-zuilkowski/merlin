# Phase 151a — CHM: Real ITSF/HTML Metadata and Text Extraction Tests

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Current state: CHM metadata uses `recover_title()` fallback; CHM text uses `recover_readable_text()` fallback. No ITSF container parsing exists.

## Problem

CHM files (Microsoft HTML Help) are a common format for technical documentation. The current stub handler scans raw binary for readable strings — it cannot reach the `<title>` tag, `<meta>` author, or structured HTML content inside the ITSF container. Plan calls for the `chmlib` crate to parse the ITSF container, locate the HHC (TOC) and home/default HTML page, extract real metadata, and return full HTML text.

## New surface introduced in phase 151b

- `metadata/chm.rs`: replace `recover_title()` fallback with `chmlib`-based ITSF parse → locate HHC TOC → locate default HTML page → extract `<title>` and `<meta name="author">` via `scraper` crate
- `text/chm.rs`: replace `recover_readable_text()` fallback with ITSF parse → iterate all HTML pages in the container → strip tags via regex → return full text + word count
- `Cargo.toml`: add `chmlib` to `[dependencies]`

## TDD coverage

File — `processing/tests/chm_metadata_tests.rs`:

- `test_chm_extracts_title_from_html` — fixture CHM with `<title>Test CHM Book</title>` → metadata title is "Test CHM Book"
- `test_chm_extracts_author_from_meta` — fixture CHM with `<meta name="author" content="Jane Author">` → metadata authors contains "Jane Author"
- `test_chm_falls_back_to_recover_title_when_no_html` — corrupt CHM (valid ITSF header, no usable HTML pages) → falls back to `recover_title()` producing a non-None title from filename stem
- `test_chm_text_strips_html_tags` — fixture CHM with two HTML pages containing `<p>Hello</p>` and `<p>World</p>` → extracted text contains "Hello World", word count = 2
- `test_chm_text_handles_empty_container` — valid ITSF with no HTML content → `ExtractedText { full_text: "", word_count: 0 }`

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- chm_metadata 2>&1 | tail -10
# Expected: compilation errors — chmlib import, new types not yet defined (phase 151b will fix)
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/chm_metadata_tests.rs
git commit -m "Phase 151a — CHM ITSF/HTML tests (failing)"
```
