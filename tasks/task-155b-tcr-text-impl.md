# Task 155b — TCR text extraction implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 155a complete: TCR tests in place and failing.

## Edit: processing/src/text/tcr.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

/// TCR format: 256 variable-length null-terminated C-strings (lookup table),
/// followed by a body where each byte is an index into that table.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    // Parse the lookup table: read exactly 256 null-terminated strings.
    let mut table: Vec<&[u8]> = Vec::with_capacity(256);
    let mut pos = 0usize;
    while table.len() < 256 {
        if pos >= data.len() {
            // Truncated file — return empty rather than panic.
            return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
        }
        // Find the null terminator for this entry.
        let end = data[pos..].iter().position(|&b| b == 0)
            .map(|i| pos + i)
            .unwrap_or(data.len());
        table.push(&data[pos..end]);
        pos = end + 1; // skip the null terminator
    }

    // Everything after the table is the body.
    let body = &data[pos..];
    if body.is_empty() {
        return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
    }

    // Decode: each byte in body is an index into the table.
    let mut decoded = Vec::with_capacity(body.len() * 4);
    for &idx in body {
        decoded.extend_from_slice(table[idx as usize]);
    }

    let full_text = String::from_utf8_lossy(&decoded)
        .chars()
        .filter(|c| c.is_ascii_graphic() || matches!(c, ' ' | '\n' | '\r' | '\t'))
        .collect::<String>();
    let word_count = full_text.split_whitespace().count();

    Ok(ExtractedText { full_text, word_count })
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test tcr_text_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep -E '^error'
```
Expected: all 3 TCR tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/text/tcr.rs
git commit -m "Task 155b — TCR text extraction: header-driven table decode"
```
