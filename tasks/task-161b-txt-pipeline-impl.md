# Phase 161b — TXT pipeline implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 161a complete: TXT tests failing.

## Create: processing/src/text/txt.rs

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

/// Plain text extraction: read the file as UTF-8, replacing invalid sequences.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let raw = std::fs::read(path).map_err(ProcessingError::IoError)?;
    let full_text = String::from_utf8_lossy(&raw).into_owned();
    let word_count = full_text.split_whitespace().count();
    Ok(ExtractedText { full_text, word_count })
}
```

## Edit: processing/src/text/mod.rs

Add the `txt` module. Find the line listing existing modules and add:
```rust
pub mod txt;
```

## Edit: processing/src/pipeline/text.rs

Find the `DetectedFormat::Txt => return Ok(()),` line and replace with:
```rust
        DetectedFormat::Txt => crate::text::txt::extract(path)?,
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test txt_pipeline_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all 3 TXT tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/text/txt.rs processing/src/text/mod.rs processing/src/pipeline/text.rs
git commit -m "Phase 161b — TXT pipeline: plain-text UTF-8 extraction"
```
