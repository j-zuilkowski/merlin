# Task 156a — SNB text extraction tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 155b complete.

New surface introduced in task 156b:
  - `crate::text::snb::extract(path)` — extracts text from SNB ZIP container's XML chapter files

## Write to: processing/tests/snb_text_tests.rs

```rust
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::text::snb::extract;

fn make_snb_zip(chapters: &[(&str, &str)]) -> Vec<u8> {
    // chapters: (zip entry path, xml content)
    use std::io::Cursor;
    let buf = Cursor::new(Vec::new());
    let mut zip = zip::ZipWriter::new(buf);
    let opts = zip::write::FileOptions::<()>::default()
        .compression_method(zip::CompressionMethod::Stored);
    for (name, content) in chapters {
        zip.start_file(*name, opts).unwrap();
        zip.write_all(content.as_bytes()).unwrap();
    }
    zip.finish().unwrap().into_inner()
}

#[test]
fn snb_extracts_chapter_text() {
    let xml = r#"<?xml version="1.0"?><snbf><ch id="c1"><p>Hello SNB world</p></ch></snbf>"#;
    let data = make_snb_zip(&[("snbf/chapter01.xml", xml)]);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert!(result.full_text.contains("Hello SNB world"),
        "expected text in {:?}", result.full_text);
    assert!(result.word_count >= 3);
}

#[test]
fn snb_multiple_chapters_concatenated() {
    let ch1 = r#"<snbf><ch><p>First chapter</p></ch></snbf>"#;
    let ch2 = r#"<snbf><ch><p>Second chapter</p></ch></snbf>"#;
    let data = make_snb_zip(&[("snbf/ch1.xml", ch1), ("snbf/ch2.xml", ch2)]);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert!(result.full_text.contains("First"));
    assert!(result.full_text.contains("Second"));
}

#[test]
fn snb_empty_zip_returns_empty() {
    let data = make_snb_zip(&[]);
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(&data).unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.word_count, 0);
}
```

## Add to processing/Cargo.toml (if not already present)
```toml
[[test]]
name = "snb_text_tests"
path = "tests/snb_text_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test snb_text_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: tests fail (snb::extract still uses recover_readable_text).

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/snb_text_tests.rs processing/Cargo.toml
git commit -m "Task 156a — SNB text extraction tests (failing)"
```
