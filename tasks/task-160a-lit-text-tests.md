# Task 160a — LIT text extraction tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 159b complete.

New surface in task 160b:
  - `crate::text::lit::extract(path)` — scans LIT binary for embedded HTML fragments

## Write to: processing/tests/lit_text_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::text::lit::extract;

/// LIT uses LZX compression internally; we can't easily generate valid compressed LIT.
/// Instead test the HTML-fragment scanning on synthetic data that mimics what leaks
/// through the binary — LIT files embed HTML chapter content even in compressed form.
fn make_lit_with_html(html_content: &str) -> Vec<u8> {
    let mut out = Vec::new();
    // LIT magic: "ITOLITLS"
    out.extend_from_slice(b"ITOLITLS");
    out.extend_from_slice(&[0u8; 24]); // header padding
    // Embed HTML content (in real LIT files some HTML survives compression partially)
    out.extend_from_slice(html_content.as_bytes());
    out
}

#[test]
fn lit_extracts_html_text_content() {
    let html = "<html><body><p>The quick brown fox</p><p>jumped over the lazy dog</p></body></html>";
    let data = make_lit_with_html(html);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert!(result.full_text.contains("quick brown"),
        "expected text content, got: {:?}", result.full_text);
    assert!(result.word_count >= 5);
}

#[test]
fn lit_wrong_magic_returns_empty() {
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(b"NOTLIT\x00\x00").unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.word_count, 0);
}

#[test]
fn lit_no_html_content_returns_empty() {
    let data = make_lit_with_html(""); // just header, no HTML
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.word_count, 0);
}
```

## Add to processing/Cargo.toml
```toml
[[test]]
name = "lit_text_tests"
path = "tests/lit_text_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test lit_text_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/lit_text_tests.rs processing/Cargo.toml
git commit -m "Task 160a — LIT text extraction tests (failing)"
```
