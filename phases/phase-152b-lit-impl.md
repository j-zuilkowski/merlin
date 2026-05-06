# Phase 152b — LIT: OPF Metadata Extraction

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 152a complete: LIT tests written and failing (expected — updated metadata extractor not yet implemented).

## Edit: `processing/src/metadata/lit.rs`

Replace the current `recover_title`-only implementation with OPF metadata scanning:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::path::Path;

/// LIT (Microsoft Reader) — magic bytes: "ITOLITLS" at offset 0.
/// Scans the container for the `/meta` entry containing an OPF metadata block.
/// The OPF format in LIT is binary-tagged — ASCII field labels with length-prefixed
/// or null-terminated string values. No LZX decompression is needed for metadata.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    // Locate the "/meta" entry marker in the file.
    // LIT containers store entries with ASCII path strings terminated by NUL or
    // preceded by length bytes. We scan for the literal b"/meta" followed by
    // the OPF metadata blob.
    let meta_marker = b"/meta";
    let mut title = None;
    let mut author = None;

    if let Some(meta_pos) = data
        .windows(meta_marker.len())
        .position(|window| window == meta_marker)
    {
        // The OPF metadata follows the /meta entry name.
        // Search for standard OPF tag markers: "TITLE=", "AUTHOR="
        // These appear as ASCII strings in the metadata blob.
        let search_start = (meta_pos + meta_marker.len()).min(data.len());
        let meta_region = &data[search_start..];

        // Extract title: look for "TITLE=" marker
        if let Some(title_pos) = find_ascii_marker(meta_region, b"TITLE=") {
            if let Some(value) = read_null_terminated(&meta_region[title_pos + 6..]) {
                title = Some(value);
            }
        }

        // Extract author: look for "AUTHOR=" marker
        if let Some(author_pos) = find_ascii_marker(meta_region, b"AUTHOR=") {
            if let Some(value) = read_null_terminated(&meta_region[author_pos + 7..]) {
                author = Some(value);
            }
        }
    }

    if title.is_none() {
        title = crate::utils::recover::recover_title(path)?;
    }

    let authors = author.map(|a| vec![a]).unwrap_or_default();

    Ok(BookMetadata {
        title,
        authors,
        ..BookMetadata::default()
    })
}

/// Find a byte sequence in the data, returning the byte offset.
fn find_ascii_marker(data: &[u8], marker: &[u8]) -> Option<usize> {
    data.windows(marker.len())
        .position(|window| window == marker)
}

/// Read a null-terminated ASCII string from a byte slice.
/// Returns None if no valid string is found within the first 256 bytes.
fn read_null_terminated(data: &[u8]) -> Option<String> {
    let end = data.iter().take(256).position(|&b| b == 0)?;
    let bytes = &data[..end];
    std::str::from_utf8(bytes)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- lit_metadata 2>&1 | grep -E 'test result|FAILED|error'
# Expected: all 4 LIT tests pass

cargo clippy --workspace -- -D warnings 2>&1 | tail -5
# Expected: zero warnings
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/lit.rs \
        processing/tests/lit_metadata_tests.rs
git commit -m "Phase 152b — LIT OPF metadata extraction from container /meta entry"
```
