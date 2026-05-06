# Phase 163a — PDB metadata completeness tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 162b complete.

Phase 154b wrote failing tests for PDB eReader metadata. Those tests exist at:
`processing/tests/pdb_ereader_tests.rs` — check if this file exists.
If it does, skip writing tests (just verify they still fail against the current stub).
If it does NOT exist, write it now.

New surface in phase 163b:
  - `crate::metadata::pdb::extract(path)` — reads creator ID + eReader metadata record (title, author, publisher, ISBN)

## Check first:
```bash
ls ~/Documents/localProject/xcalibre/processing/tests/pdb_ereader_tests.rs 2>/dev/null \
  && echo "EXISTS — skip writing tests, just verify they fail" \
  || echo "MISSING — write tests below"
```

## If MISSING, write to: processing/tests/pdb_ereader_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::metadata::pdb::extract;

/// Build a minimal PDB header (78 bytes) + record list + eReader record.
fn make_ereader_pdb(title: &str, author: &str) -> Vec<u8> {
    let mut out = Vec::new();

    // 32-byte name field
    let mut name = [0u8; 32];
    let nb = title.as_bytes().len().min(31);
    name[..nb].copy_from_slice(&title.as_bytes()[..nb]);
    out.extend_from_slice(&name);

    // 28 bytes reserved
    out.extend_from_slice(&[0u8; 28]);

    // Creator ID at offset 60: "PNPdPPrs" (eReader)
    out.extend_from_slice(b"PNPdPPrs");

    // 8 bytes padding to reach offset 76
    out.extend_from_slice(&[0u8; 8]);

    // num_records at offset 76: 2 records (record 0 = eReader header, record 1 = metadata)
    out.extend_from_slice(&2u16.to_be_bytes());

    // The header is now 78 bytes. Record list follows: 2 × 8 bytes = 16 bytes.
    // Record 0 starts right after record list + 2-byte gap = 78 + 16 + 2 = 96
    let rec0_offset: u32 = 96;
    // Record 1 starts after record 0 (132 bytes) = 96 + 132 = 228
    let rec1_offset: u32 = 228;

    // Record list entry 0
    out.extend_from_slice(&rec0_offset.to_be_bytes());
    out.extend_from_slice(&[0u8; 4]); // flags + reserved

    // Record list entry 1
    out.extend_from_slice(&rec1_offset.to_be_bytes());
    out.extend_from_slice(&[0u8; 4]);

    // 2-byte gap
    out.extend_from_slice(&[0u8; 2]);

    // === Record 0: 132-byte eReader header ===
    assert_eq!(out.len(), 96);
    let mut ereader_hdr = [0u8; 132];
    // has_metadata at offset 24: 1
    ereader_hdr[24] = 0;
    ereader_hdr[25] = 1;
    // metadata_index at offset 44: record 1
    ereader_hdr[44] = 0;
    ereader_hdr[45] = 1;
    out.extend_from_slice(&ereader_hdr);

    // === Record 1: metadata (null-separated fields) ===
    assert_eq!(out.len(), 228);
    // Format: title\0author\0\0publisher\0isbn\0
    out.extend_from_slice(title.as_bytes());
    out.push(0);
    out.extend_from_slice(author.as_bytes());
    out.push(0);
    out.push(0); // empty field (separator)

    out
}

#[test]
fn pdb_ereader_extracts_title() {
    let data = make_ereader_pdb("eReader Book Title", "eReader Author");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let meta = extract(f.path()).unwrap();
    assert_eq!(meta.title.as_deref(), Some("eReader Book Title"));
}

#[test]
fn pdb_ereader_extracts_author() {
    let data = make_ereader_pdb("Title", "Jane Doe");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let meta = extract(f.path()).unwrap();
    assert!(meta.authors.contains(&"Jane Doe".to_string()));
}

#[test]
fn pdb_non_ereader_returns_name_field() {
    let mut data = vec![0u8; 78];
    let name = b"Plain PDB Book";
    data[..name.len()].copy_from_slice(name);
    // Creator at offset 60: not eReader
    data[60..68].copy_from_slice(b"BOOKMOBI");
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let meta = extract(f.path()).unwrap();
    assert_eq!(meta.title.as_deref(), Some("Plain PDB Book"));
}
```

## Add to processing/Cargo.toml (if not already present)
```toml
[[test]]
name = "pdb_ereader_tests"
path = "tests/pdb_ereader_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test pdb_ereader_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail (current pdb.rs only reads 32-byte name).

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/pdb_ereader_tests.rs processing/Cargo.toml
git commit -m "Phase 163a — PDB eReader metadata tests (failing)"
```
