# Phase 163b — PDB metadata completeness implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 163a complete: PDB eReader tests failing.

## Edit: processing/src/metadata/pdb.rs

Replace the entire file:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::io::{Read, Seek};
use std::path::Path;

/// PDB (Palm Database) metadata extractor.
/// For generic PDBs: reads the 32-byte name field as title.
/// For eReader PDBs (creator `PNPdPPrs` / `PNRdPPrs`): parses the eReader header
/// in record 0 to locate a metadata record containing title, author, publisher, ISBN.
pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let mut file = std::fs::File::open(path).map_err(ProcessingError::IoError)?;

    // Full PDB header is 78 bytes.
    let mut header = [0u8; 78];
    match file.read_exact(&mut header) {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
            return read_name_only(path);
        }
        Err(e) => return Err(ProcessingError::IoError(e)),
    }

    // 32-byte name field (null-terminated).
    let fallback_title = parse_cstring(&header[..32]);

    // Creator ID at offset 60 (8 bytes).
    let creator = &header[60..68];
    if creator == b"PNPdPPrs" || creator == b"PNRdPPrs" {
        if let Ok(meta) = read_ereader_metadata(&mut file, &header, fallback_title.clone()) {
            return Ok(meta);
        }
    }

    Ok(BookMetadata { title: fallback_title, ..BookMetadata::default() })
}

fn read_ereader_metadata(
    file: &mut std::fs::File,
    header: &[u8; 78],
    fallback_title: Option<String>,
) -> Result<BookMetadata, ProcessingError> {
    let num_records = u16::from_be_bytes([header[76], header[77]]) as usize;
    if num_records < 2 {
        return Ok(BookMetadata { title: fallback_title, ..BookMetadata::default() });
    }

    // Record list: 8 bytes per entry starting right after the 78-byte header.
    let mut offsets: Vec<u64> = Vec::with_capacity(num_records);
    for _ in 0..num_records {
        let mut entry = [0u8; 8];
        file.read_exact(&mut entry).map_err(ProcessingError::IoError)?;
        offsets.push(u32::from_be_bytes([entry[0], entry[1], entry[2], entry[3]]) as u64);
    }

    // 2-byte gap after record list.
    let mut gap = [0u8; 2];
    file.read_exact(&mut gap).map_err(ProcessingError::IoError)?;

    // Record 0: 132-byte eReader header.
    let mut hdr = [0u8; 132];
    if file.read_exact(&mut hdr).is_err() {
        return Ok(BookMetadata { title: fallback_title, ..BookMetadata::default() });
    }

    let has_meta = u16::from_be_bytes([hdr[24], hdr[25]]);
    if has_meta == 0 {
        return Ok(BookMetadata { title: fallback_title, ..BookMetadata::default() });
    }

    let meta_idx = u16::from_be_bytes([hdr[44], hdr[45]]) as usize;
    if meta_idx == 0 || meta_idx >= num_records {
        return Ok(BookMetadata { title: fallback_title, ..BookMetadata::default() });
    }

    let meta_offset = offsets[meta_idx];
    let meta_end = offsets.get(meta_idx + 1).copied().unwrap_or(u64::MAX);
    let max_len = ((meta_end.saturating_sub(meta_offset)) as usize).min(2048);

    file.seek(std::io::SeekFrom::Start(meta_offset))
        .map_err(ProcessingError::IoError)?;
    let mut buf = vec![0u8; max_len];
    let n = file.read(&mut buf).map_err(ProcessingError::IoError)?;
    buf.truncate(n);

    // Metadata record: null-separated UTF-8 fields.
    // Field order: title, author, (empty separator), publisher, isbn
    let fields: Vec<String> = buf
        .split(|&b| b == 0)
        .filter_map(|s| std::str::from_utf8(s).ok())
        .map(|s| s.trim().to_string())
        .collect();

    let title  = fields.first().cloned().filter(|s| !s.is_empty()).or(fallback_title);
    let author = fields.get(1).cloned().filter(|s| !s.is_empty());
    let publisher = fields.get(3).cloned().filter(|s| !s.is_empty());
    let isbn   = fields.get(4).cloned().filter(|s| !s.is_empty());

    Ok(BookMetadata {
        title,
        authors:   author.map(|a| vec![a]).unwrap_or_default(),
        publisher,
        isbn,
        ..BookMetadata::default()
    })
}

fn read_name_only(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let mut file = std::fs::File::open(path).map_err(ProcessingError::IoError)?;
    let mut buf = [0u8; 32];
    let n = file.read(&mut buf).map_err(ProcessingError::IoError)?;
    Ok(BookMetadata { title: parse_cstring(&buf[..n]), ..BookMetadata::default() })
}

fn parse_cstring(bytes: &[u8]) -> Option<String> {
    let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    std::str::from_utf8(&bytes[..end]).ok()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
}
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test pdb_ereader_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo test --package xcalibre-processing 2>&1 | tail -5
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all PDB tests pass, full test suite passes, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/metadata/pdb.rs
git commit -m "Phase 163b — PDB eReader metadata: creator-ID detection + record-0 title/author/publisher/ISBN"
```
