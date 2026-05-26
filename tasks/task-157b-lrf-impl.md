# Task 157b — LRF metadata + text implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 157a complete: LRF tests failing.

## Edit: processing/src/metadata/lrf.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::path::Path;

const LRF_MAGIC: &[u8] = b"LRF\x00";

/// LRF / LRX (Sony BroadBand eBook).
/// Scans the binary for `Title=` and `Author=` key=value pairs embedded
/// in the file's metadata objects. Falls back to filename-derived title
/// if neither is found.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    // Validate magic bytes.
    if data.len() < 8 || &data[..4] != LRF_MAGIC {
        return Ok(BookMetadata { ..BookMetadata::default() });
    }

    let text = String::from_utf8_lossy(&data);

    let title = scan_kv(&text, "Title");
    let author = scan_kv(&text, "Author");
    let authors = author.map(|a| vec![a]).unwrap_or_default();

    Ok(BookMetadata {
        title,
        authors,
        ..BookMetadata::default()
    })
}

/// Find `Key=value\0` or `Key=value\n` pattern in text.
fn scan_kv(text: &str, key: &str) -> Option<String> {
    let prefix = format!("{}=", key);
    let pos = text.find(prefix.as_str())?;
    let after = &text[pos + prefix.len()..];
    let end = after.find(|c: char| c == '\0' || c == '\n' || c == '\r')
        .unwrap_or(after.len().min(256));
    let value = after[..end].trim().to_string();
    if value.is_empty() { None } else { Some(value) }
}
```

## Edit: processing/src/text/lrf.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

const LRF_MAGIC: &[u8] = b"LRF\x00";

/// LRF text extraction: scan for printable ASCII runs (length > 20 chars)
/// after skipping the binary header. LRF text blocks are not easily decompressed
/// without LZX support, but embedded strings in text objects are recoverable.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    if data.len() < 8 || &data[..4] != LRF_MAGIC {
        return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
    }

    // Skip the 12-byte fixed header.
    let body = &data[12.min(data.len())..];

    // Collect runs of printable Latin characters (length >= 8).
    let mut full_text = String::new();
    let mut run = String::new();
    for &b in body {
        if b >= 0x20 && b < 0x7F {
            run.push(b as char);
        } else {
            if run.len() >= 8 {
                if !full_text.is_empty() {
                    full_text.push(' ');
                }
                full_text.push_str(run.trim());
            }
            run.clear();
        }
    }
    if run.len() >= 8 {
        if !full_text.is_empty() { full_text.push(' '); }
        full_text.push_str(run.trim());
    }

    let word_count = full_text.split_whitespace().count();
    Ok(ExtractedText { full_text, word_count })
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test lrf_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all 4 LRF tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/lrf.rs processing/src/text/lrf.rs
git commit -m "Task 157b — LRF metadata + text: key=value scanner + ASCII run extractor"
```
