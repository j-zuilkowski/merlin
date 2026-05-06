# Phase 158a — DjVu metadata + text tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 157b complete.

New surface in phase 158b:
  - `crate::metadata::djvu::extract(path)` — reads full file for Annot metadata (not just 2KB)
  - `crate::text::djvu::extract(path)` — parses IFF structure to find and decompress TXTz chunks

## Write to: processing/tests/djvu_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::metadata::djvu::extract as meta_extract;
use xcalibre_processing::text::djvu::extract as text_extract;

/// Build a minimal DjVu IFF file.
/// Structure: "AT&TFORM" + u32be(total_size) + "DJVU" + chunks...
/// Each chunk: 4-byte ID + u32be(size) + data (padded to even length).
fn iff_chunk(id: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut chunk = Vec::new();
    chunk.extend_from_slice(id);
    chunk.extend_from_slice(&(data.len() as u32).to_be_bytes());
    chunk.extend_from_slice(data);
    if data.len() % 2 != 0 { chunk.push(0); }
    chunk
}

fn make_djvu(chunks: &[Vec<u8>]) -> Vec<u8> {
    let mut body = b"DJVU".to_vec();
    for c in chunks { body.extend_from_slice(c); }
    let mut out = Vec::new();
    out.extend_from_slice(b"AT&TFORM");
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    out.extend_from_slice(&body);
    out
}

fn make_txtz(text: &str) -> Vec<u8> {
    // TXTz = zlib-compressed DjVu text layer
    use flate2::write::ZlibEncoder;
    use flate2::Compression;
    // Minimal DjVu text: "(page 0 0 600 800\n (line 0 0 600 20\n \"text\"))"
    let djvu_text = format!("(page 0 0 600 800 (line 0 0 600 20 \"{}\"))", text);
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(djvu_text.as_bytes()).unwrap();
    encoder.finish().unwrap()
}

#[test]
fn djvu_metadata_reads_title_beyond_2kb() {
    // Put the metadata annotation after 2048 bytes of padding to verify full-file scan
    let padding = vec![b' '; 2100];
    let annot_data = format!(
        "(metadata\n (title \"DjVu Test Book\")\n (author \"Test Author\")\n)"
    );
    let mut body = b"DJVU".to_vec();
    body.extend_from_slice(&padding);
    body.extend_from_slice(annot_data.as_bytes());

    let mut out = Vec::new();
    out.extend_from_slice(b"AT&TFORM");
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    out.extend_from_slice(&body);

    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&out).unwrap();
    let meta = meta_extract(f.path()).unwrap();
    assert_eq!(meta.title.as_deref(), Some("DjVu Test Book"));
    assert!(meta.authors.contains(&"Test Author".to_string()));
}

#[test]
fn djvu_text_extracts_txtz_chunk() {
    let compressed = make_txtz("Hello DjVu world");
    let txtz_chunk = iff_chunk(b"TXTz", &compressed);
    let data = make_djvu(&[txtz_chunk]);

    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = text_extract(f.path()).unwrap();
    assert!(result.full_text.contains("Hello DjVu world"),
        "got: {:?}", result.full_text);
    assert!(result.word_count >= 3);
}

#[test]
fn djvu_text_no_txtz_returns_empty() {
    // DjVu with only an INFO chunk (no text layer)
    let info = iff_chunk(b"INFO", &[0u8; 10]);
    let data = make_djvu(&[info]);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = text_extract(f.path()).unwrap();
    assert_eq!(result.word_count, 0);
}
```

## Add to processing/Cargo.toml
```toml
[[test]]
name = "djvu_tests"
path = "tests/djvu_tests.rs"
```

Also ensure `flate2` is in `[dev-dependencies]` (it should already be present for SNB tests).

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test djvu_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail (current djvu extractors are stubs).

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/djvu_tests.rs processing/Cargo.toml
git commit -m "Phase 158a — DjVu metadata + text tests (failing)"
```
