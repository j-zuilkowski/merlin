# S2 Fixture Build — ledger

Builds the S2 capability fixture: a Rust workspace (library `ledger` + binary
`ledger-cli`) with 6 planted defects, plus its `golden/` reference.

## Layout (decided)
- **Working copy (buggy)** → `merlin-eval/fixtures/rust-buggy/` — what Merlin opens. All
  6 defects.
- **Golden (correct)** → `merlin-eval/fixtures/rust-golden/` — sibling, never inside the
  working copy. Diff/scoring reference.

## Note on the manifest
S2's manifest lists both **RL3** and **RL5** at "`total_for`". They cannot share one
implementation (a filter vs. a map lookup), so the fixture realises them as two methods:
`total_for` (filters entries — carries **RL3**) and `lookup_total` (a checked map lookup —
carries **RL5**). The CLI surfaces them as `report` and `total <category>` respectively.
Update the S2 manifest's RL5 row to read "`Ledger::lookup_total`". Behaviour and cues
are unchanged. `parallel_total` and `lookup_total` are additions beyond the manifest's
method list — noted here as fixture-author realisation.

---

## Part 1 — the correct workspace

Write these files under `merlin-eval/fixtures/rust-golden/`.

### `Cargo.toml` (workspace root)
```toml
[workspace]
members = ["ledger", "ledger-cli"]
resolver = "2"
```

### `ledger/Cargo.toml`
```toml
[package]
name = "ledger"
version = "0.1.0"
edition = "2021"
```

### `ledger/src/lib.rs`
```rust
//! A small expense-ledger library.
use std::collections::HashMap;
use std::thread;

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub amount_cents: i64,
    pub category: String,
}

#[derive(Debug, Default)]
pub struct Ledger {
    entries: Vec<Entry>,
}

impl Ledger {
    pub fn new() -> Self {
        Ledger { entries: Vec::new() }
    }

    pub fn add(&mut self, amount_cents: i64, category: &str) {
        self.entries.push(Entry {
            amount_cents,
            category: category.to_string(),
        });
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Sum of every entry.
    pub fn total(&self) -> i64 {
        self.entries.iter().map(|e| e.amount_cents).sum()
    }

    /// The ledger balance — total of all entries.
    pub fn balance(&self) -> i64 {
        self.total()
    }

    /// Total for one category, by filtering the entries.
    pub fn total_for(&self, category: &str) -> i64 {
        self.entries
            .iter()
            .filter(|e| e.category == category)
            .map(|e| e.amount_cents)
            .sum()
    }

    /// Checked per-category lookup via a totals map. Unknown category → 0.
    pub fn lookup_total(&self, category: &str) -> i64 {
        let mut totals: HashMap<&str, i64> = HashMap::new();
        for e in &self.entries {
            *totals.entry(e.category.as_str()).or_insert(0) += e.amount_cents;
        }
        totals.get(category).copied().unwrap_or(0)
    }

    /// Distinct categories, sorted.
    pub fn categories(&self) -> Vec<String> {
        let mut cats: Vec<String> =
            self.entries.iter().map(|e| e.category.clone()).collect();
        cats.sort();
        cats.dedup();
        cats
    }

    fn entry_chunks(&self) -> Vec<Vec<i64>> {
        self.entries
            .chunks(4)
            .map(|c| c.iter().map(|e| e.amount_cents).collect())
            .collect()
    }

    /// Sums the ledger across worker threads — every handle is joined.
    pub fn parallel_total(&self) -> i64 {
        let total = std::sync::Arc::new(std::sync::Mutex::new(0i64));
        let mut handles = Vec::new();
        for chunk in self.entry_chunks() {
            let total = std::sync::Arc::clone(&total);
            handles.push(thread::spawn(move || {
                let partial: i64 = chunk.iter().sum();
                *total.lock().unwrap() += partial;
            }));
        }
        for h in handles {
            h.join().unwrap();
        }
        let result = *total.lock().unwrap();
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Ledger {
        let mut l = Ledger::new();
        l.add(1200, "food");
        l.add(3400, "rent");
        l.add(800, "food");
        l
    }

    #[test]
    fn total_sums_every_entry() {                 // RL1
        assert_eq!(sample().total(), 5400);
    }

    #[test]
    fn total_does_not_overflow_on_a_large_ledger() {  // RL2
        let mut l = Ledger::new();
        for _ in 0..1000 {
            l.add(50_000_000, "big");
        }
        // `as i64` / `_i64` keep this compiling under both widths (golden i64,
        // buggy i32); the buggy `total()` panics on overflow before the assert.
        assert_eq!(l.total() as i64, 50_000_000_000_i64);
    }

    #[test]
    fn total_for_returns_only_that_category() {   // RL3
        assert_eq!(sample().total_for("food"), 2000);
    }

    #[test]
    fn lookup_total_unknown_category_is_zero() {  // RL5
        assert_eq!(sample().lookup_total("travel"), 0);
    }

    #[test]
    fn parallel_total_always_equals_total() {     // RL6
        let mut l = Ledger::new();
        for i in 0..200 {
            // no cast on `i` — its width is inferred from `add`, so this
            // compiles under both the golden (i64) and buggy (i32) versions.
            l.add(i * 10, "x");
        }
        for _ in 0..50 {
            assert_eq!(l.parallel_total(), l.total());
        }
    }
}
```

### `ledger-cli/Cargo.toml`
```toml
[package]
name = "ledger-cli"
version = "0.1.0"
edition = "2021"

[dependencies]
ledger = { path = "../ledger" }
```

### `ledger-cli/src/main.rs`
```rust
//! ledger-cli — `add <cents> <category>`, `total [category]`, `report`.
//! State persists to `./ledger.txt` (one `amount_cents\tcategory` per line).
use ledger::Ledger;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(out) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Err(msg) => {
            eprintln!("error: {msg}");
            ExitCode::FAILURE
        }
    }
}

const STORE: &str = "ledger.txt";

fn run(args: &[String]) -> Result<String, String> {
    let cmd = args.first().map(String::as_str).unwrap_or("");
    match cmd {
        "add" => {
            let cents_arg = args.get(1).ok_or("usage: add <cents> <category>")?;
            let category = args.get(2).ok_or("usage: add <cents> <category>")?;
            let cents: i64 = cents_arg.parse().map_err(|_| {
                format!("invalid amount '{cents_arg}' — expected an integer of cents")
            })?;
            append(cents, category)?;
            Ok(format!("added {cents} to {category}\n"))
        }
        "total" => {
            let ledger = load()?;
            if let Some(category) = args.get(1) {
                Ok(format!("{}\n", ledger.lookup_total(category)))
            } else {
                Ok(format!("{}\n", ledger.total()))
            }
        }
        "report" => {
            let ledger = load()?;
            let mut out = String::new();
            for c in ledger.categories() {
                out.push_str(&format!("{c}: {}\n", ledger.total_for(&c)));
            }
            Ok(out)
        }
        other => Err(format!("unknown command '{other}'")),
    }
}

fn append(cents: i64, category: &str) -> Result<(), String> {
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(STORE)
        .map_err(|e| e.to_string())?;
    writeln!(f, "{cents}\t{category}").map_err(|e| e.to_string())
}

fn load() -> Result<Ledger, String> {
    let mut ledger = Ledger::new();
    let text = match std::fs::read_to_string(STORE) {
        Ok(t) => t,
        Err(_) => return Ok(ledger),
    };
    for line in text.lines() {
        let mut parts = line.splitn(2, '\t');
        if let (Some(c), Some(cat)) = (parts.next(), parts.next()) {
            if let Ok(cents) = c.parse::<i64>() {
                ledger.add(cents, cat);
            }
        }
    }
    Ok(ledger)
}
```

### `ledger-cli/tests/cli.rs`
```rust
use std::process::Command;

/// RL4 — `add` must reject a non-numeric amount, not silently accept it.
#[test]
fn add_rejects_non_numeric_amount() {
    let dir = std::env::temp_dir().join(format!("ledgercli-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let exe = env!("CARGO_BIN_EXE_ledger-cli");

    let out = Command::new(exe)
        .args(["add", "abc", "food"])
        .current_dir(&dir)
        .output()
        .unwrap();

    assert!(
        !out.status.success(),
        "`add abc food` must fail — a non-numeric amount is an error, not a 0 entry"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
```

---

## Part 2 — snapshot golden

The files above are the correct workspace. Build + test once (see Verify) to confirm
green, then that tree **is** `rust-golden/`. Copy it to the working copy:
```
cp -R merlin-eval/fixtures/rust-golden merlin-eval/fixtures/rust-buggy
```

---

## Part 3 — inject the 6 defects into `rust-buggy/` only

| ID | File | Change |
|----|------|--------|
| **RL1** off-by-one | `ledger/src/lib.rs` | `total()`: change `self.entries.iter()` → `self.entries[1..].iter()` (skips the first entry). |
| **RL2** overflow | `ledger/src/lib.rs` | Change the integer width from `i64` to `i32` in the **production code only**: `Entry.amount_cents: i32`; the return types of `total`, `balance`, `total_for`, `lookup_total`, `parallel_total`; the `HashMap<&str, i64>` and `Mutex<0i64>`/`partial: i64`/`Vec<Vec<i64>>` element types; and `entry_chunks`. **Do NOT touch the `#[cfg(test)] mod tests` block** — it is the detection harness, authored in Part 1 to compile under both widths; its `total() as i64` and `50_000_000_000_i64` literal must stay `i64` (a blanket find-replace of `i64`→`i32` here re-creates the "literal out of range" compile error). (One defect — the integer width — realised across every production use. The fix is the reverse: `i64` throughout.) |
| **RL3** wrong operator | `ledger/src/lib.rs` | `total_for()`: change the filter `e.category == category` → `e.category != category`. |
| **RL4** swallowed error | `ledger-cli/src/main.rs` | The `add` branch: replace `cents_arg.parse().map_err(|_| …)?` with `cents_arg.parse().unwrap_or(0)` — bad input silently becomes a 0 entry. |
| **RL5** panic | `ledger/src/lib.rs` | `lookup_total()`: change `totals.get(category).copied().unwrap_or(0)` → `*totals.get(category).unwrap()` — panics for an unknown category. |
| **RL6** concurrency | `ledger/src/lib.rs` | `parallel_total()`: change `handles.push(thread::spawn(move || { … }))` → `thread::spawn(move || { … });` (do not collect the handle) and **delete** the `for h in handles { h.join().unwrap(); }` loop and the `let mut handles = Vec::new();` line. Threads are detached; `result` is read before they finish. |

Six logic / error-handling / concurrency defects.

Note — under RL2, the `#[cfg(test)]` test `total_does_not_overflow_on_a_large_ledger`
sums to `50_000_000_000`, which overflows `i32`: a debug build panics, a release build
wraps to a wrong total. That is the intended RL2 cue.

---

## Verify
```
# Golden — correct: builds clean, all tests pass, release build correct.
cd merlin-eval/fixtures/rust-golden
cargo build && cargo test && cargo build --release
cargo run -q -p ledger-cli -- add abc food ; echo "exit=$?"   # expect exit=1

# Buggy — compiles, but cargo test is red.
cd ../rust-buggy
cargo build 2>&1 | tail -3
cargo test 2>&1 | grep -E 'test result|FAILED|panicked'
```
Expected:
- **golden:** `cargo build`/`test`/`build --release` all clean; every test passes;
  `add abc food` exits non-zero.
- **buggy:** `cargo build` succeeds (it compiles). `cargo test` is **red** —
  `total_sums_every_entry` (RL1), `total_for_returns_only_that_category` (RL3),
  `lookup_total_unknown_category_is_zero` (RL5, panics), `parallel_total_always_equals_total`
  (RL6), `add_rejects_non_numeric_amount` (RL4), and
  `total_does_not_overflow_on_a_large_ledger` (RL2 — panics in debug) all fail.

`rust-golden/` is never opened by Merlin during the S2 run; it is the scoring diff base.
