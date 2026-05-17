//! A small expense-ledger library.
use std::collections::HashMap;
use std::thread;

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub amount_cents: i32,
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

    pub fn add(&mut self, amount_cents: i32, category: &str) {
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
    pub fn total(&self) -> i32 {
        self.entries[1..].iter().map(|e| e.amount_cents).sum()
    }

    /// The ledger balance - total of all entries.
    pub fn balance(&self) -> i32 {
        self.total()
    }

    /// Total for one category, by filtering the entries.
    pub fn total_for(&self, category: &str) -> i32 {
        self.entries
            .iter()
            .filter(|e| e.category != category)
            .map(|e| e.amount_cents)
            .sum()
    }

    /// Checked per-category lookup via a totals map. Unknown category returns 0.
    pub fn lookup_total(&self, category: &str) -> i32 {
        let mut totals: HashMap<&str, i32> = HashMap::new();
        for e in &self.entries {
            *totals.entry(e.category.as_str()).or_insert(0) += e.amount_cents;
        }
        *totals.get(category).unwrap()
    }

    /// Distinct categories, sorted.
    pub fn categories(&self) -> Vec<String> {
        let mut cats: Vec<String> =
            self.entries.iter().map(|e| e.category.clone()).collect();
        cats.sort();
        cats.dedup();
        cats
    }

    fn entry_chunks(&self) -> Vec<Vec<i32>> {
        self.entries
            .chunks(4)
            .map(|c| c.iter().map(|e| e.amount_cents).collect())
            .collect()
    }

    /// Sums the ledger across worker threads - every handle is joined.
    pub fn parallel_total(&self) -> i32 {
        let total = std::sync::Arc::new(std::sync::Mutex::new(0i32));
        for chunk in self.entry_chunks() {
            let total = std::sync::Arc::clone(&total);
            thread::spawn(move || {
                let partial: i32 = chunk.iter().sum();
                *total.lock().unwrap() += partial;
            });
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
    fn total_sums_every_entry() {
        assert_eq!(sample().total(), 5400);
    }

    #[test]
    fn total_does_not_overflow_on_a_large_ledger() {
        let mut l = Ledger::new();
        for _ in 0..1000 {
            l.add(50_000_000, "big");
        }
        // `as i64` / `_i64` keep this compiling under both widths (golden i64,
        // buggy i32); the buggy `total()` panics on overflow before the assert.
        assert_eq!(l.total() as i64, 50_000_000_000_i64);
    }

    #[test]
    fn total_for_returns_only_that_category() {
        assert_eq!(sample().total_for("food"), 2000);
    }

    #[test]
    fn lookup_total_unknown_category_is_zero() {
        assert_eq!(sample().lookup_total("travel"), 0);
    }

    #[test]
    fn parallel_total_always_equals_total() {
        let mut l = Ledger::new();
        for i in 0..200 {
            // no cast on `i` - its width is inferred from `add`, so this
            // compiles under both the golden (i64) and buggy (i32) versions.
            l.add(i * 10, "x");
        }
        for _ in 0..50 {
            assert_eq!(l.parallel_total(), l.total());
        }
    }
}
