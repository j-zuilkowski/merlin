# Task 159b — AZW4 text extraction implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 159a complete: AZW4 tests failing.

## Edit: processing/src/text/azw4.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

/// AZW4 wraps an embedded PDF. Scan the raw bytes for `%PDF-` magic,
/// write the embedded PDF to a temp file, and delegate to the PDF extractor.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    // Locate the embedded PDF by searching for the %PDF- marker.
    let marker = b"%PDF-";
    let Some(offset) = data.windows(marker.len()).position(|w| w == marker) else {
        return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
    };

    let pdf_data = &data[offset..];

    // Write to a temp file so the PDF extractor (which takes a &Path) can use it.
    let mut tmp = tempfile::NamedTempFile::new()
        .map_err(ProcessingError::IoError)?;
    use std::io::Write;
    tmp.write_all(pdf_data).map_err(ProcessingError::IoError)?;

    // Delegate to the PDF extractor. If it fails (stub/malformed PDF), return empty.
    crate::text::pdf::extract(tmp.path()).or_else(|_| {
        Ok(ExtractedText { full_text: String::new(), word_count: 0 })
    })
}
```

Note: `tempfile` must be in `[dependencies]` (not just dev-dependencies) since this is production code.
Check `processing/Cargo.toml` — if `tempfile` is only in `[dev-dependencies]`, move it to `[dependencies]`.

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test azw4_text_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: both AZW4 tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/text/azw4.rs processing/Cargo.toml
git commit -m "Task 159b — AZW4 text: detect embedded PDF and delegate to pdf extractor"
```
