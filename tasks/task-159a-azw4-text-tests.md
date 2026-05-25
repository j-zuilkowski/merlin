# Task 159a — AZW4 text extraction tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 158b complete.

New surface in task 159b:
  - `crate::text::azw4::extract(path)` — detects embedded PDF and delegates to pdf extractor

## Write to: processing/tests/azw4_text_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::text::azw4::extract;

/// AZW4 wraps an embedded PDF. Build a fake AZW4 with %PDF marker inside.
fn make_azw4_with_pdf(pdf_text: &str) -> Vec<u8> {
    let mut out = Vec::new();
    // Fake PalmDOC/MOBI header (78 bytes of zeros, creator "BOOK"/"MOBI")
    out.extend_from_slice(&[0u8; 60]);
    out.extend_from_slice(b"BOOKMOBI"); // creator
    out.extend_from_slice(&[0u8; 10]);
    // Embed a minimal "PDF" stub that the extractor should detect
    let pdf_stub = format!("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\nBT\n({}) Tj\nET\n%%EOF",
        pdf_text);
    out.extend_from_slice(pdf_stub.as_bytes());
    out
}

#[test]
fn azw4_detects_embedded_pdf() {
    let data = make_azw4_with_pdf("embedded pdf content");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    // The extractor should find %PDF- and attempt PDF extraction.
    // Since our stub PDF is not a real PDF, we just assert it does not panic
    // and returns some result (possibly empty for a stub PDF).
    let result = extract(f.path());
    assert!(result.is_ok(), "should not error: {:?}", result.err());
}

#[test]
fn azw4_no_embedded_pdf_returns_empty() {
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(b"BOOKMOBI\x00\x00\x00\x00no pdf here").unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.word_count, 0);
}
```

## Add to processing/Cargo.toml
```toml
[[test]]
name = "azw4_text_tests"
path = "tests/azw4_text_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test azw4_text_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/azw4_text_tests.rs processing/Cargo.toml
git commit -m "Task 159a — AZW4 text extraction tests (failing)"
```
