# S2 — Rust Logic Debug Cycle

Proves Merlin can build a Rust project, run its tests, detect logic / concurrency /
error-handling defects, fix them, and re-verify. Logic-only — Rust has no GUI surface
here; "the same as S1" means the debug cycle, not visual bugs.

---

## Fixture: `ledger`

Location: `merlin-eval/fixtures/rust-buggy/`

A Rust workspace — a small expense-ledger: a library crate (`ledger`) plus a binary
(`ledger-cli`). **Build the correct project first, snapshot to `golden/`, then inject the
six defects.** `golden/` is the diff reference; never given to Merlin.

### Intended (correct) behaviour
- `ledger` lib: `Ledger` holds `entries: Vec<Entry>` (`Entry { amount_cents: i64,
  category: String }`); methods `add`, `total()`, `balance()`, `total_for(category)`,
  `categories()`.
- `ledger-cli` bin: parses `add <cents> <category>`, `total`, `report` subcommands.
- `cargo test` suite in `ledger/tests/` and `#[cfg(test)]` modules asserting correct
  arithmetic, filtering, and parse behaviour — all green on the correct project.

### Planted-defect manifest

| ID | Kind | Location | Defect | Expected fix | Detection cue |
|----|------|----------|--------|--------------|---------------|
| **RL1** | logic / off-by-one | `ledger/src/lib.rs` — `total()` | Sums `&self.entries[1..]`, skipping the first entry | Sum all entries | `total` test fails; CLI total is short by the first entry |
| **RL2** | logic / overflow | `ledger/src/lib.rs` — `amount_cents` typed `i32`; `total()` returns `i32` | Large ledgers overflow `i32` | Use `i64` throughout | overflow panic (debug) / wrong total (release) on a big ledger |
| **RL3** | logic / wrong operator | `ledger/src/lib.rs` — `total_for(category)` filter | Filters `e.category != category` (negated) | Use `==` | category report returns the wrong entries |
| **RL4** | error handling / swallowed | `ledger-cli/src/main.rs` — argument parse | `cents.parse::<i64>().unwrap_or(0)` — bad input silently becomes 0 | Return a real error / reject bad input | `add abc food` silently adds a 0 entry instead of erroring |
| **RL5** | error handling / panic | `ledger/src/lib.rs` — `lookup_total` | `totals.get(category).unwrap()` panics for an unknown category | Return `0` for an absent category (`unwrap_or(0)`) | `lookup_total("unknown")` panics instead of returning 0 |
| **RL6** | concurrency | `ledger/src/lib.rs` — `parallel_total()` | Spawns worker threads but drops the `JoinHandle`s without `join()` — partial/nondeterministic sum | Collect and `join()` all handles before summing | `parallel_total()` disagrees with `total()` and varies run to run |

Six logic defects. Tests cover RL1–RL5 deterministically; RL6 is caught by a test that
runs `parallel_total()` many times and asserts it always equals `total()`.

---

## Scenario prompt (given to Merlin)

> The Rust project at `merlin-eval/fixtures/rust-buggy/` is an expense-ledger library and
> CLI. Build it with `cargo build`, run `cargo test`, and exercise the CLI (`add`,
> `total`, `report`). It has several logic, error-handling, and concurrency bugs. Find
> every defect, fix it in the source, and re-verify until `cargo test` is fully green and
> the CLI behaves correctly. Report each defect, its root cause, the fix, and how you
> confirmed it.

---

## Scoring rubric

**Deterministic (harness-checkable):**
- [ ] `cargo build` clean before and after.
- [ ] `cargo test` — red on the injected project (RL1, RL3, RL5, RL6 tests at least),
      fully green after Merlin's fixes.
- [ ] CLI: `add abc food` is rejected with an error, not silently accepted (RL4).
- [ ] `cargo build --release` total is correct on a large ledger (RL2).
- [ ] Final diff vs. `golden/` touches only the six defect sites — no unrelated churn.

**Judgment (transcript review):**
- [ ] Merlin diagnosed each bug from evidence (test output, run output) rather than
      guessing — especially RL2 (overflow) and RL6 (concurrency), which need reasoning.

**Score:** defects fixed / 6, plus pass/fail on "no unrelated churn" and "sound process".

---

## Runsheet

1. Batches B–D merged; Merlin built; LM Studio running; DeepSeek key present.
2. Build the fixture, run `cargo test`, record which tests are red.
3. Launch Merlin, open the `rust-buggy` fixture as the project.
4. Send the scenario prompt. **Dictation cue:** speak the prompt via the mic button this
   time; confirm transcription before sending.
5. Let Merlin run; watch it build, test, and debug.
6. When done: run `cargo test` and `cargo build --release` yourself; exercise the CLI.
7. Score against the rubric; write `merlin-eval/results/S2-<date>.md`.
8. Missed or mis-fixed defects are findings — record them for the Merlin backlog.
