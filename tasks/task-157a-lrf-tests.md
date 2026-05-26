# Task 157a — LRF metadata + text tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 156b complete.

New surface in task 157b:
  - `crate::metadata::lrf::extract(path)` — parses title/author from LRF object header
  - `crate::text::lrf::extract(path)` — scans LRF text blocks for readable content

## Write to: processing/tests/lrf_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::metadata::lrf::extract as meta_extract;
use xcalibre_processing::text::lrf::extract as text_extract;

/// Minimal LRF binary: magic + version + xor_key + object_count + padding,
/// followed by an embedded title/author string in the body for scanning.
fn make_lrf(title: &str, author: &str, text_content: &str) -> Vec<u8> {
    let mut out = Vec::new();
    // LRF magic: "LRF\0"
    out.extend_from_slice(b"LRF\x00");
    // version: 999 as u16le
    out.extend_from_slice(&999u16.to_le_bytes());
    // xor_key: 0 as u16le
    out.extend_from_slice(&0u16.to_le_bytes());
    // object_count placeholder: 0 as u32le
    out.extend_from_slice(&0u32.to_le_bytes());
    // Embed simple key=value metadata that our scanner can find
    out.extend_from_slice(format!("Title={}\0Author={}\0", title, author).as_bytes());
    // Embed text content
    out.extend_from_slice(text_content.as_bytes());
    out
}

#[test]
fn lrf_metadata_extracts_title() {
    let data = make_lrf("My LRF Book", "Jane Author", "");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let meta = meta_extract(f.path()).unwrap();
    assert_eq!(meta.title.as_deref(), Some("My LRF Book"));
}

#[test]
fn lrf_metadata_extracts_author() {
    let data = make_lrf("Title", "John Smith", "");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let meta = meta_extract(f.path()).unwrap();
    assert!(meta.authors.contains(&"John Smith".to_string()));
}

#[test]
fn lrf_text_extracts_content() {
    let data = make_lrf("", "", "The quick brown fox");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = text_extract(f.path()).unwrap();
    assert!(result.full_text.contains("quick brown"), "{:?}", result.full_text);
    assert!(result.word_count >= 3);
}

#[test]
fn lrf_wrong_magic_returns_defaults() {
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(b"NOTLRF\x00\x00\x00\x00").unwrap();
    // Should not panic; returns empty/default
    let meta = meta_extract(f.path()).unwrap();
    assert!(meta.title.is_none() || meta.title.as_deref() == Some(""));
}
```

## Add to processing/Cargo.toml
```toml
[[test]]
name = "lrf_tests"
path = "tests/lrf_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test lrf_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/lrf_tests.rs processing/Cargo.toml
git commit -m "Task 157a — LRF metadata + text tests (failing)"
```
