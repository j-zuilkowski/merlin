# Phase 161a — TXT pipeline tests (failing)

## Context
Rust 2021, cargo workspace. No new warnings. Clippy clean.
Working dir: ~/Documents/localProject/xcalibre
Phase 160b complete.

New surface in phase 161b:
  - `crate::text::txt::extract(path)` — reads plain text file as UTF-8
  - `pipeline::text::run_text` handles `DetectedFormat::Txt` via `txt::extract`

## Write to: processing/tests/txt_pipeline_tests.rs

```rust
use sqlx::sqlite::SqlitePoolOptions;
use std::io::Write;
use tempfile::NamedTempFile;
use xcalibre_processing::pipeline::ingest::run_ingest;
use xcalibre_processing::pipeline::text::run_text;
use xcalibre_processing::text::txt::extract;

async fn setup_db() -> sqlx::Pool<sqlx::Sqlite> {
    let pool = SqlitePoolOptions::new()
        .connect("sqlite::memory:")
        .await
        .unwrap();
    sqlx::migrate!("src/db/migrations").run(&pool).await.unwrap();
    pool
}

#[test]
fn txt_extract_returns_content() {
    let mut f = NamedTempFile::with_suffix(".txt").unwrap();
    f.write_all(b"Hello plain text world\nSecond line here").unwrap();
    let result = extract(f.path()).unwrap();
    assert!(result.full_text.contains("Hello plain text world"));
    assert!(result.word_count >= 6);
}

#[test]
fn txt_extract_empty_file() {
    let f = NamedTempFile::with_suffix(".txt").unwrap();
    let result = extract(f.path()).unwrap();
    assert_eq!(result.full_text, "");
    assert_eq!(result.word_count, 0);
}

#[tokio::test]
async fn txt_pipeline_inserts_text_row() {
    let pool = setup_db().await;
    let path = std::path::PathBuf::from("tests/fixtures/fixture_txt.txt");
    let ingest = run_ingest(&pool, &path).await.unwrap();
    run_text(&pool, &ingest, &path).await.unwrap();
    let row: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM job_text WHERE job_id = ?")
        .bind(&ingest.job_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(row.0, 1);
}
```

## Add to processing/Cargo.toml
```toml
[[test]]
name = "txt_pipeline_tests"
path = "tests/txt_pipeline_tests.rs"
```

## Verify
```bash
cd ~/Documents/localProject/xcalibre
cargo test --package xcalibre-processing --test txt_pipeline_tests 2>&1 | grep -E 'FAILED|error\[|^error'
```
Expected: compile error — `crate::text::txt` does not exist.

## Commit
```bash
cd ~/Documents/localProject/xcalibre
git add processing/tests/txt_pipeline_tests.rs processing/Cargo.toml
git commit -m "Phase 161a — TXT pipeline tests (failing)"
```
