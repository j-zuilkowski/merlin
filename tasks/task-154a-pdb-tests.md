# Phase 154a — PDB/eReader: Metadata Header Reading Tests

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Current state: PDB metadata reads only the 32-byte name field from the PDB header. All PDB sub-formats (eReader, Plucker, PalmDOC) are treated identically. The creator ID at offset 60 is not inspected.

## Problem

PDB (Palm Database) files have a creator ID field (8 bytes at offset 60) that identifies the sub-format. For eReader PDBs with creator `PNPdPPrs` or `PNRdPPrs`, the first record is a 132-byte eReader header containing a `has_metadata` flag and `metadata_offset` field that points to a metadata record with title, author, publisher, and ISBN fields. The current stub ignores all of this — it returns only the 32-byte name as the title. No new crate dependency is needed.

## New surface introduced in phase 154b

- `metadata/pdb.rs`: read creator ID at offset 60 → if `PNPdPPrs` or `PNRdPPrs`, parse the 132-byte eReader header → read metadata record at `metadata_offset` → extract title, author, publisher, ISBN from null-separated fields

## TDD coverage

File — `processing/tests/pdb_ereader_tests.rs`:

- `test_pdb_ereader_metadata_title` — fixture eReader PDB (creator `PNPdPPrs`) with metadata record containing "Test eBook Title\0Jane Author\0\0Test Publisher\01234567890\0" → metadata title is "Test eBook Title"
- `test_pdb_ereader_author_and_publisher` — fixture eReader PDB (creator `PNRdPPrs`) with metadata record → metadata authors contains "Jane Author", publisher is "Test Publisher"
- `test_pdb_ereader_isbn` — fixture eReader PDB with ISBN in metadata record → metadata isbn is "1234567890"
- `test_pdb_ereader_falls_back_to_name_when_has_metadata_is_zero` — eReader PDB with `has_metadata = 0` → falls back to 32-byte name field
- `test_pdb_non_ereader_still_uses_name_field` — PalmDOC PDB with `TEXtREAd` creator → returns name field as title, no eReader header parsing attempted
- `test_pdb_text_extraction_unchanged` — PalmDOC PDB → text extraction still works (no regression on existing text/pdb.rs)

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- pdb_ereader 2>&1 | tail -10
# Expected: compilation errors — new PDB eReader parser not yet implemented (phase 154b will fix)
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/pdb_ereader_tests.rs
git commit -m "Phase 154a — PDB eReader metadata tests (failing)"
```
