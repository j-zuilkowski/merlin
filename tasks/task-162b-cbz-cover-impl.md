# Task 162b — CBZ/CBR cover extraction implementation

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Task 162a complete: CBZ cover tests failing.

## Create: processing/src/cover/cbz.rs

```rust
use crate::cover::CoverResult;
use crate::error::ProcessingError;
use std::io::Read;
use std::path::Path;

const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"];

/// Extract the first (alphabetically) image entry from a CBZ (ZIP) archive.
/// CBR archives use the same heuristic if `unrar` is not available; for now
/// only CBZ (ZIP) is supported — CBR returns Ok(None).
pub fn extract(path: &Path) -> Result<Option<CoverResult>, ProcessingError> {
    let ext = path.extension()
        .and_then(|e| e.to_str())
        .map(str::to_lowercase)
        .unwrap_or_default();

    if ext == "cbr" {
        // RAR support requires external `unrar` binary; not implemented.
        return Ok(None);
    }

    let file = std::fs::File::open(path).map_err(ProcessingError::IoError)?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| ProcessingError::ParseError(e.to_string()))?;

    // Collect image entry names and sort alphabetically.
    let mut image_names: Vec<String> = (0..archive.len())
        .filter_map(|i| archive.by_index(i).ok().map(|e| e.name().to_owned()))
        .filter(|name| {
            let lower = name.to_lowercase();
            // Skip macOS __MACOSX metadata entries
            if lower.contains("__macosx") { return false; }
            let ext = lower.rsplit('.').next().unwrap_or("");
            IMAGE_EXTENSIONS.contains(&ext)
        })
        .collect();

    image_names.sort();

    let first = match image_names.first() {
        Some(n) => n.clone(),
        None => return Ok(None),
    };

    let mut entry = archive
        .by_name(&first)
        .map_err(|e| ProcessingError::ParseError(e.to_string()))?;

    let mut data = Vec::new();
    entry.read_to_end(&mut data).map_err(ProcessingError::IoError)?;

    if data.is_empty() {
        return Ok(None);
    }

    let mime_type = mime_for_ext(first.rsplit('.').next().unwrap_or(""));

    Ok(Some(CoverResult { data, mime_type, width: 0, height: 0 }))
}

fn mime_for_ext(ext: &str) -> String {
    match ext.to_lowercase().as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png"          => "image/png",
        "gif"          => "image/gif",
        "webp"         => "image/webp",
        "bmp"          => "image/bmp",
        _              => "image/jpeg",
    }
    .to_string()
}
```

## Edit: processing/src/cover/mod.rs

Add the `cbz` module:
```rust
pub mod cbz;
```

## Edit: processing/src/pipeline/cover.rs

Find the `_ => return Ok(None),` wildcard arm and replace with:
```rust
        DetectedFormat::Cbz => crate::cover::cbz::extract(path)?,
        DetectedFormat::Cbr => crate::cover::cbz::extract(path)?,  // CBR: returns Ok(None) internally
        _ => return Ok(None),
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test cbz_cover_tests 2>&1 | grep -E 'test result|FAILED|error'
cargo clippy --package xcalibre-processing -- -D warnings 2>&1 | grep '^error'
```
Expected: all 3 CBZ tests pass, no clippy errors.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/src/cover/cbz.rs processing/src/cover/mod.rs processing/src/pipeline/cover.rs
git commit -m "Task 162b — CBZ cover extraction: first alphabetical image from ZIP"
```
