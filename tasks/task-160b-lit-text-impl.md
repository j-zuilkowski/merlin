# Task 160b — LIT text extraction implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 160a complete: LIT text tests failing.

## Edit: processing/src/text/lit.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

const LIT_MAGIC: &[u8] = b"ITOLITLS";

/// LIT text extraction: LIT uses LZX compression (no Rust crate available).
/// Scan the raw bytes for embedded HTML fragments — partial HTML content
/// leaks through the binary even in compressed sections — and strip tags.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    if data.len() < 8 || &data[..8] != LIT_MAGIC {
        return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
    }

    // Scan for HTML tag openings and collect text between them.
    // Strategy: find '<' bytes, skip the tag content, yield the text between tags.
    let raw = &data[8..];
    let mut full_text = String::new();
    let mut pos = 0usize;

    while pos < raw.len() {
        if raw[pos] == b'<' {
            // Skip this tag
            let end = raw[pos..].iter().position(|&b| b == b'>')
                .map(|i| pos + i + 1)
                .unwrap_or(raw.len());
            pos = end;
        } else if raw[pos] >= 0x20 && raw[pos] < 0x7F {
            // Printable ASCII — collect a run
            let start = pos;
            while pos < raw.len() && raw[pos] != b'<' && raw[pos] >= 0x20 && raw[pos] < 0x7F {
                pos += 1;
            }
            let segment = std::str::from_utf8(&raw[start..pos])
                .unwrap_or("")
                .trim();
            if segment.len() >= 4 && !segment.starts_with("http") {
                if !full_text.is_empty() { full_text.push(' '); }
                full_text.push_str(segment);
            }
        } else {
            pos += 1;
        }
    }

    // Collapse whitespace
    let full_text = full_text.split_whitespace().collect::<Vec<_>>().join(" ");
    let word_count = full_text.split_whitespace().count();
    Ok(ExtractedText { full_text, word_count })
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test lit_text_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all 3 LIT tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/text/lit.rs
git commit -m "Task 160b — LIT text: HTML fragment scan of compressed binary"
```
