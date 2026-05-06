# Phase 155a — TCR text extraction tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 154b complete.

New surface introduced in phase 155b:
  - `crate::text::tcr::extract(path)` — returns ExtractedText with actual decoded content

## Write to: processing/tests/tcr_text_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::text::tcr::extract;

/// Build a minimal valid TCR file.
/// Format: 256 variable-length C-strings (lookup table), then body bytes (indices into table).
fn make_tcr(table: &[&str; 256], body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for entry in table {
        out.extend_from_slice(entry.as_bytes());
        out.push(0u8); // null terminator
    }
    out.extend_from_slice(body);
    out
}

#[test]
fn tcr_decodes_simple_text() {
    // Build table: entry 0 = "Hello", entry 1 = " world", rest = empty strings
    let mut table = [""; 256];
    table[0] = "Hello";
    table[1] = " world";
    // body: indices [0, 1] => "Hello world"
    let data = make_tcr(&table, &[0u8, 1u8]);

    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert!(result.full_text.contains("Hello"), "expected 'Hello' in {:?}", result.full_text);
    assert!(result.full_text.contains("world"), "expected 'world' in {:?}", result.full_text);
    assert!(result.word_count >= 2);
}

#[test]
fn tcr_empty_body_returns_empty() {
    let table = [""; 256];
    let data = make_tcr(&table, &[]);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.full_text, "");
    assert_eq!(result.word_count, 0);
}

#[test]
fn tcr_too_short_returns_empty() {
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(b"ab").unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.full_text, "");
}
```

## Add to processing/Cargo.toml (if not already present)
```toml
[[test]]
name = "tcr_text_tests"
path = "tests/tcr_text_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test tcr_text_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: BUILD FAILED or tests fail (implementation not updated yet).

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/tcr_text_tests.rs processing/Cargo.toml
git commit -m "Phase 155a — TCR text extraction tests (failing)"
```
