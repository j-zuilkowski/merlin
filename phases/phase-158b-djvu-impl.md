# Phase 158b — DjVu metadata + text implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 158a complete: DjVu tests failing.

Check that `flate2` is in `[dependencies]` of `processing/Cargo.toml`. If not, add:
```toml
flate2 = "1"
```

## Edit: processing/src/metadata/djvu.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::path::Path;

/// DjVu — IFF-based format (AT&TFORM/DJVU).
/// Scans the full file for `(metadata ...)` Annot blocks containing
/// title and author key-value pairs.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;
    let text = String::from_utf8_lossy(&data);

    let title = scan_djvu_kv(&text, "title");
    let author = scan_djvu_kv(&text, "author");
    let authors = author.map(|a| vec![a]).unwrap_or_default();

    Ok(BookMetadata { title, authors, ..BookMetadata::default() })
}

/// Scan for `(key "value")` or `(key 'value')` patterns in DjVu annotation syntax.
fn scan_djvu_kv(text: &str, key: &str) -> Option<String> {
    let prefix = format!("({} ", key);
    let pos = text.find(prefix.as_str())?;
    let after = &text[pos + prefix.len()..];
    // Value is quoted with " or '
    let (open, close) = if after.starts_with('"') { ('"', '"') } else { ('\'', '\'') };
    if after.starts_with(open) {
        let inner = &after[1..];
        let end = inner.find(close)?;
        let value = inner[..end].trim().to_string();
        if value.is_empty() { None } else { Some(value) }
    } else {
        // Unquoted value up to closing paren
        let end = after.find(')')?;
        let value = after[..end].trim().to_string();
        if value.is_empty() { None } else { Some(value) }
    }
}
```

## Edit: processing/src/text/djvu.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::io::Read;
use std::path::Path;

const DJVU_MAGIC: &[u8] = b"AT&TFORM";

/// DjVu text extraction: parse the IFF chunk structure to locate TXTz chunks
/// (zlib-compressed hidden text layer), decompress and extract the text strings.
pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    if data.len() < 12 || &data[..8] != DJVU_MAGIC {
        return Ok(ExtractedText { full_text: String::new(), word_count: 0 });
    }

    // Skip AT&TFORM header (8 bytes size field + 4 bytes "DJVU") = offset 12.
    let mut full_text = String::new();
    let mut pos = 12usize;

    while pos + 8 <= data.len() {
        let id = &data[pos..pos + 4];
        let size = u32::from_be_bytes([
            data[pos + 4], data[pos + 5], data[pos + 6], data[pos + 7],
        ]) as usize;
        pos += 8;

        let end = (pos + size).min(data.len());
        let chunk_data = &data[pos..end];

        if id == b"TXTz" {
            if let Ok(text) = decompress_txtz(chunk_data) {
                let extracted = extract_djvu_text_strings(&text);
                if !extracted.is_empty() {
                    if !full_text.is_empty() { full_text.push(' '); }
                    full_text.push_str(&extracted);
                }
            }
        }

        // Advance past chunk (padded to even byte boundary).
        pos += if size % 2 == 0 { size } else { size + 1 };
    }

    let word_count = full_text.split_whitespace().count();
    Ok(ExtractedText { full_text, word_count })
}

fn decompress_txtz(data: &[u8]) -> Result<String, ProcessingError> {
    use std::io::Read;
    let mut decoder = flate2::read::ZlibDecoder::new(data);
    let mut out = String::new();
    decoder.read_to_string(&mut out)
        .map_err(|e| ProcessingError::ParseError(e.to_string()))?;
    Ok(out)
}

/// Extract quoted string content from DjVu text layer S-expressions.
/// Format: `(page ... (line ... "text1") (line ... "text2") ...)`
fn extract_djvu_text_strings(s_expr: &str) -> String {
    let mut result = String::new();
    let mut in_quote = false;
    let mut current = String::new();

    for ch in s_expr.chars() {
        match ch {
            '"' if !in_quote => in_quote = true,
            '"' if in_quote => {
                in_quote = false;
                let trimmed = current.trim().to_string();
                if !trimmed.is_empty() {
                    if !result.is_empty() { result.push(' '); }
                    result.push_str(&trimmed);
                }
                current.clear();
            }
            _ if in_quote => current.push(ch),
            _ => {}
        }
    }
    result
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test djvu_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all 3 DjVu tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/djvu.rs processing/src/text/djvu.rs processing/Cargo.toml
git commit -m "Phase 158b — DjVu metadata full-file scan + TXTz text layer extraction"
```
