# Task 154b — PDB/eReader: Metadata Header Reading

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 154a complete: PDB eReader tests written and failing (expected — updated metadata extractor not yet implemented).

## Edit: `processing/src/metadata/pdb.rs`

Replace the current name-field-only implementation with creator-ID inspection and eReader metadata parsing:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::io::Read;
use std::path::Path;

/// PDB (Palm Database) / PML / RB — 32-byte header with name at offset 0.
/// For eReader PDBs (creator `PNPdPPrs` or `PNRdPPrs`), the first record
/// contains a 132-byte eReader header that points to a metadata record with
/// title, author, publisher, and ISBN.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let mut file = std::fs::File::open(path).map_err(ProcessingError::IoError)?;
    let mut header = [0u8; 78];
    // Read the full PDB header: 32-byte name + 28 reserved + 8 creator + 8 num_sections/padding + 2 gap
    match file.read_exact(&mut header) {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
            // File too small — fall back to name field only.
            return pdb_name_fallback(path);
        }
        Err(e) => return Err(ProcessingError::IoError(e)),
    }

    // Name field: first 32 bytes, null-terminated.
    let name_bytes = header[..32]
        .split(|&byte| byte == 0)
        .next()
        .unwrap_or(&header[..32]);
    let fallback_title = std::str::from_utf8(name_bytes)
        .ok()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(String::from);

    // Creator ID at offset 60 (8 bytes).
    let creator = &header[60..68];

    if creator == b"PNPdPPrs" || creator == b"PNRdPPrs" {
        // eReader PDB: Read record list to locate record 0 (eReader header).
        return read_ereader_metadata(&mut file, &header, fallback_title);
    }

    Ok(BookMetadata {
        title: fallback_title,
        ..BookMetadata::default()
    })
}

fn read_ereader_metadata(
    file: &mut std::fs::File,
    header: &[u8; 78],
    fallback_title: Option<String>,
) -> Result<BookMetadata, ProcessingError> {
    // Number of records at offset 76–77 (big-endian u16).
    let num_records = u16::from_be_bytes([header[76], header[77]]) as usize;
    if num_records == 0 {
        return Ok(BookMetadata {
            title: fallback_title,
            ..BookMetadata::default()
        });
    }

    // Record list: 8 bytes per record (offset: u32be, flags: u8, val: u24be).
    let mut record_offsets = Vec::with_capacity(num_records);
    for _ in 0..num_records {
        let mut entry = [0u8; 8];
        file.read_exact(&mut entry).map_err(ProcessingError::IoError)?;
        let offset = u32::from_be_bytes([entry[0], entry[1], entry[2], entry[3]]) as u64;
        record_offsets.push(offset);
    }

    // 2-byte gap after record list.
    let mut gap = [0u8; 2];
    file.read_exact(&mut gap).map_err(ProcessingError::IoError)?;

    // Record 0: 132-byte eReader header.
    let mut ereader_hdr = [0u8; 132];
    file.read_exact(&mut ereader_hdr)
        .map_err(ProcessingError::IoError)?;

    // has_metadata: u16 at offset 24.
    let has_metadata = u16::from_be_bytes([ereader_hdr[24], ereader_hdr[25]]);
    if has_metadata == 0 {
        return Ok(BookMetadata {
            title: fallback_title,
            ..BookMetadata::default()
        });
    }

    // metadata_offset: u16 at offset 44 — which record index holds the metadata.
    let metadata_idx = u16::from_be_bytes([ereader_hdr[44], ereader_hdr[45]]) as usize;
    if metadata_idx == 0 || metadata_idx >= num_records {
        return Ok(BookMetadata {
            title: fallback_title,
            ..BookMetadata::default()
        });
    }

    // Seek to the metadata record and read it.
    let meta_record_offset = record_offsets[metadata_idx];
    let next_offset = if metadata_idx + 1 < num_records {
        record_offsets[metadata_idx + 1]
    } else {
        // Read remaining file as the last record.
        u64::MAX
    };

    let meta_len = (next_offset.saturating_sub(meta_record_offset)) as usize;
    // Cap at 2048 bytes — metadata records are small.
    let meta_len = meta_len.min(2048);

    use std::io::Seek;
    file.seek(std::io::SeekFrom::Start(meta_record_offset))
        .map_err(ProcessingError::IoError)?;
    let mut meta_bytes = vec![0u8; meta_len];
    let read_len = file.read(&mut meta_bytes).map_err(ProcessingError::IoError)?;
    meta_bytes.truncate(read_len);

    // eReader metadata format: null-separated fields.
    // title\0author\0\0publisher\0isbn\0
    let fields: Vec<String> = meta_bytes
        .split(|&b| b == 0)
        .filter_map(|chunk| {
            std::str::from_utf8(chunk)
                .ok()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
        })
        .collect();

    let title = fields.first().cloned().or(fallback_title);
    let author = fields.get(1).cloned();
    // Field 2 is typically empty (double null separator).
    let publisher = fields.get(3).cloned();
    let isbn = fields.get(4).cloned();

    let authors = author.map(|a| vec![a]).unwrap_or_default();

    Ok(BookMetadata {
        title,
        authors,
        publisher,
        isbn,
        ..BookMetadata::default()
    })
}

fn pdb_name_fallback(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let mut file = std::fs::File::open(path).map_err(ProcessingError::IoError)?;
    let mut name_bytes = [0u8; 32];
    // Use read (not read_exact) to handle files smaller than 32 bytes.
    let n = file.read(&mut name_bytes).map_err(ProcessingError::IoError)?;
    let name = name_bytes[..n]
        .split(|&byte| byte == 0)
        .next()
        .unwrap_or(&[]);
    let title = std::str::from_utf8(name)
        .ok()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(String::from);
    Ok(BookMetadata {
        title,
        ..BookMetadata::default()
    })
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- pdb_ereader 2>&1 | grep -E 'test result|FAILED|error'
# Expected: all 6 PDB eReader tests pass

cargo test --package xcalibre-processing 2>&1 | tail -5
# Expected: all tests pass (no regressions in existing format tests)

cargo clippy --workspace -- -D warnings 2>&1 | tail -5
# Expected: zero warnings
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/pdb.rs \
        processing/tests/pdb_ereader_tests.rs
git commit -m "Task 154b — PDB eReader metadata header reading (title, author, publisher, ISBN)"
```
