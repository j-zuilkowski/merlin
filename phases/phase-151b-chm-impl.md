# Phase 151b — CHM: Real ITSF/HTML Metadata and Text Extraction

## Context
Rust 2021 edition, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 151a complete: CHM tests written and failing (expected — missing chmlib dependency and updated extractors).

## Edit: `processing/Cargo.toml`

Add under `[dependencies]`:
```toml
chmlib = "0.5"
```

## Edit: `processing/src/metadata/chm.rs`

Replace the current `recover_title`-only implementation with:

```rust
use crate::error::ProcessingError;
use crate::metadata::BookMetadata;
use std::path::Path;

pub fn extract(path: &Path) -> Result<BookMetadata, ProcessingError> {
    let file = std::fs::read(path).map_err(ProcessingError::IoError)?;
    let chm = chmlib::ChmFile::new(&file)
        .map_err(|e| ProcessingError::FormatParseError(format!("CHM ITSF parse: {e}")))?;

    let mut title = None;
    let mut authors = Vec::new();

    // Locate the home/default HTML page via the HHC (TOC) file.
    // The HHC entry in the ITSF directs us to the primary content page.
    if let Ok(home_path) = chm.home_topic() {
        if let Ok(home_bytes) = chm.get_object_bytes(&home_path) {
            // Use the existing `scraper` crate to extract <title> and <meta> tags.
            if let Ok(home_str) = std::str::from_utf8(&home_bytes) {
                let doc = scraper::Html::parse_document(home_str);
                if let Some(title_el) = doc
                    .select(&scraper::Selector::parse("title").unwrap())
                    .next()
                {
                    title = Some(
                        title_el
                            .text()
                            .collect::<Vec<_>>()
                            .join("")
                            .trim()
                            .to_string(),
                    );
                }
                for meta_el in doc.select(&scraper::Selector::parse("meta").unwrap()) {
                    if let Some(name) = meta_el.value().attr("name") {
                        if name.eq_ignore_ascii_case("author") {
                            if let Some(content) = meta_el.value().attr("content") {
                                authors.push(content.trim().to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    // Fall back to existing heuristic if no HTML title was found.
    if title.is_none() {
        title = crate::utils::recover::recover_title(path)?;
    }

    Ok(BookMetadata {
        title,
        authors,
        ..BookMetadata::default()
    })
}
```

## Edit: `processing/src/text/chm.rs`

Replace `recover_readable_text` with CHM container traversal:

```rust
use crate::error::ProcessingError;
use crate::text::ExtractedText;
use std::path::Path;

pub fn extract(path: &Path) -> Result<ExtractedText, ProcessingError> {
    let file = std::fs::read(path).map_err(ProcessingError::IoError)?;
    let chm = chmlib::ChmFile::new(&file)
        .map_err(|e| ProcessingError::FormatParseError(format!("CHM ITSF parse: {e}")))?;

    let mut all_text = String::new();

    // Iterate all objects in the CHM container, extracting text from HTML pages.
    if let Ok(topics) = chm.list_topics() {
        for topic_path in &topics {
            if let Ok(bytes) = chm.get_object_bytes(topic_path) {
                if let Ok(html_str) = std::str::from_utf8(&bytes) {
                    let stripped = strip_html_tags(html_str);
                    if !stripped.trim().is_empty() {
                        if !all_text.is_empty() {
                            all_text.push('\n');
                        }
                        all_text.push_str(&stripped);
                    }
                }
            }
        }
    }

    // Fall back to heuristic if container traversal produced nothing.
    if all_text.trim().is_empty() {
        all_text = crate::utils::recover::recover_readable_text(path)?;
    }

    let word_count = all_text.split_whitespace().count();
    Ok(ExtractedText {
        full_text: all_text,
        word_count,
    })
}

fn strip_html_tags(html: &str) -> String {
    // Simple regex HTML tag stripper matching existing patterns in the crate.
    let re = regex::Regex::new(r"<[^>]*>").unwrap();
    let stripped = re.replace_all(html, " ");
    stripped
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
```

## Edit: `processing/src/error.rs`

Add the variant if not already present:
```rust
#[error("Format parse error: {0}")]
FormatParseError(String),
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing -- chm_metadata 2>&1 | grep -E 'test result|FAILED|error'
# Expected: all 5 CHM tests pass

cargo clippy --workspace -- -D warnings 2>&1 | tail -5
# Expected: zero warnings
```

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/Cargo.toml \
        processing/src/metadata/chm.rs \
        processing/src/text/chm.rs \
        processing/src/error.rs \
        processing/tests/chm_metadata_tests.rs
git commit -m "Phase 151b — CHM real ITSF/HTML metadata and text extraction"
```
