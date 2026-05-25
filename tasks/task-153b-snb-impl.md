# Phase 153b — SNB: SNBF Container Parsing

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 153a complete: SNB tests written and failing (expected — updated metadata extractor not yet implemented).

## Edit: `processing/src/metadata/snb.rs`

Replace the current filename-only implementation with SNBF container parsing:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::path::Path;

/// SNB (Shanda Bambook) — proprietary Chinese ebook format.
/// Magic bytes: "SNBP" at offset 0.
/// The SNBF container format has section headers pointing to a file table.
/// The `book.snbf` entry contains XML metadata with title, author, publisher,
/// language, and cover.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let data = std::fs::read(path).map_err(ProcessingError::IoError)?;

    // SNBF container: after the 4-byte "SNBP" magic, the next 4 bytes are the
    // section count. Each section header is 16 bytes: 4-byte type, 4-byte offset,
    // 4-byte length, 4-byte flags/version. The file table section (type 0x02)
    // contains entries pointing to individual files in the container.
    if data.len() < 12 {
        return metadata_from_filename(path);
    }

    let section_count = u32::from_le_bytes([data[4], data[5], data[6], data[7]]) as usize;
    let mut file_table_offset = None;
    let mut file_table_length = None;

    // Parse section headers starting at offset 8.
    let mut pos = 8usize;
    for _ in 0..section_count {
        if pos + 16 > data.len() {
            break;
        }
        let section_type = u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]);
        let section_offset = u32::from_le_bytes([data[pos + 4], data[pos + 5], data[pos + 6], data[pos + 7]]) as usize;
        let section_length = u32::from_le_bytes([data[pos + 8], data[pos + 9], data[pos + 10], data[pos + 11]]) as usize;

        if section_type == 0x02 {
            // File table section
            file_table_offset = Some(section_offset);
            file_table_length = Some(section_length);
            break;
        }
        pos += 16;
    }

    let (title, mut authors, publisher, language) = match (file_table_offset, file_table_length) {
        (Some(ft_off), Some(ft_len)) => {
            // File table: each entry is a variable-length record with a name field.
            // Search for the "book.snbf" entry name within the file table region.
            let ft_end = (ft_off + ft_len).min(data.len());
            let ft_data = &data[ft_off..ft_end];
            extract_book_snbf_metadata(ft_data, &data)
        }
        _ => (None, Vec::new(), None, None),
    };

    let title = title.or_else(|| {
        metadata_from_filename(path).ok().and_then(|m| m.title)
    });

    Ok(BookMetadata {
        title,
        authors,
        publisher,
        language,
        ..BookMetadata::default()
    })
}

fn extract_book_snbf_metadata(
    ft_data: &[u8],
    full_data: &[u8],
) -> (Option<String>, Vec<String>, Option<String>, Option<String>) {
    // Search for the string "book.snbf" in the file table region.
    let marker = b"book.snbf";
    if let Some(marker_pos) = ft_data
        .windows(marker.len())
        .position(|w| w == marker)
    {
        // The file table entry format varies; after the name, the entry typically
        // contains offset (u32 LE) and length (u32 LE) to the file data.
        // Scan ahead for a plausible offset/length pair.
        let after_name = marker_pos + marker.len();
        if after_name + 8 <= ft_data.len() {
            // Try reading offset and length as little-endian u32 right after the name.
            // Some SNBF variants have padding between name and offset; try a few alignments.
            for skip in 0..8 {
                let candidate = after_name + skip;
                if candidate + 8 > ft_data.len() {
                    break;
                }
                let file_offset =
                    u32::from_le_bytes([
                        ft_data[candidate],
                        ft_data[candidate + 1],
                        ft_data[candidate + 2],
                        ft_data[candidate + 3],
                    ]) as usize;
                let file_length =
                    u32::from_le_bytes([
                        ft_data[candidate + 4],
                        ft_data[candidate + 5],
                        ft_data[candidate + 6],
                        ft_data[candidate + 7],
                    ]) as usize;

                if file_offset > 0
                    && file_length > 0
                    && file_offset + file_length <= full_data.len()
                {
                    let xml_data = &full_data[file_offset..file_offset + file_length];
                    if let Ok(xml_str) = std::str::from_utf8(xml_data) {
                        if xml_str.contains('<') && xml_str.contains('>') {
                            return parse_snbf_xml(xml_str);
                        }
                    }
                }
            }
        }
    }
    (None, Vec::new(), None, None)
}

fn parse_snbf_xml(xml: &str) -> (Option<String>, Vec<String>, Option<String>, Option<String>) {
    let doc = roxmltree::Document::parse(xml).ok();
    let title = doc
        .as_ref()
        .and_then(|d| {
            d.descendants()
                .find(|n| n.has_tag_name("title"))
                .map(|n| n.text().unwrap_or("").trim().to_string())
        })
        .filter(|s| !s.is_empty());
    let author = doc
        .as_ref()
        .and_then(|d| {
            d.descendants()
                .find(|n| n.has_tag_name("author"))
                .map(|n| n.text().unwrap_or("").trim().to_string())
        })
        .filter(|s| !s.is_empty());
    let publisher = doc
        .as_ref()
        .and_then(|d| {
            d.descendants()
                .find(|n| n.has_tag_name("publisher"))
                .map(|n| n.text().unwrap_or("").trim().to_string())
        })
        .filter(|s| !s.is_empty());
    let language = doc
        .as_ref()
        .and_then(|d| {
            d.descendants()
                .find(|n| n.has_tag_name("language"))
                .map(|n| n.text().unwrap_or("").trim().to_string())
        })
        .filter(|s| !s.is_empty());
    let authors = author.map(|a| vec![a]).unwrap_or_default();
    (title, authors, publisher, language)
}

fn metadata_from_filename(path: &Path) -> Result<BookMetadata, ProcessingError> {
    Ok(BookMetadata {
        title: path
            .file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.replace(['_', '-'], " ")),
        ..BookMetadata::default()
    })
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- snb_metadata 2>&1 | grep -E 'test result|FAILED|error'
# Expected: all 5 SNB tests pass

cargo clippy --workspace -- -D warnings 2>&1 | tail -5
# Expected: zero warnings
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/snb.rs \
        processing/tests/snb_metadata_tests.rs
git commit -m "Phase 153b — SNB SNBF container parsing with book.snbf metadata XML"
```
