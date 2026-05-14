# Codex Orchestration Prompt — Merlin v2.1.0 (Budget-Aware Execution)

Paste this entire prompt into Codex as the first message. Codex will execute phases 232–240
in strict sequence, committing after each one.

---

You are executing the Merlin **Budget-Aware Execution** overhaul, which ships as **v2.1.0**.
The work is broken into 18 phase files (nine NNa/NNb pairs covering phases 232 through 240) under
`phases/`. Each phase file is **self-contained** and includes its own context, surface list,
verify command, and commit instructions.

## Hard rules — read and obey before starting

1. **Working directory:** `~/Documents/localProject/merlin`. All commands run from there.
2. **Read `CLAUDE.md` and `architecture.md` first.** They define the project's TDD discipline,
   Swift standards, build commands, versioning policy, and constraints (Swift 5.10, macOS 14+,
   non-sandboxed, no third-party packages, `SWIFT_STRICT_CONCURRENCY=complete`, zero warnings,
   zero errors). Honor every rule. Do not relax `SWIFT_STRICT_CONCURRENCY`. The "V2.1 —
   Budget-Aware Execution" section in `architecture.md` is the architectural spec for this work
   — phases must match it, not modify it.
3. **Strict phase order.** Execute phases in this exact sequence — no reordering, no skipping,
   no merging:
   ```
   232a → 232b → 233a → 233b → 234a → 234b → 235a → 235b →
   236a → 236b → 237a → 237b → 238a → 238b → 239a → 239b →
   240a → 240b
   ```
4. **TDD discipline is non-negotiable.** Every `NNa` phase **must** end with a `BUILD FAILED`
   verification (the tests are deliberately failing because the surfaces don't yet exist) and a
   git commit of just those failing tests. Every `NNb` phase **must** end with `BUILD SUCCEEDED`
   and a passing test run before the commit. **Never** skip the failing-tests commit. **Never**
   batch commits across phases.
5. **Commit after every phase.** Use the exact `git add` and `git commit` invocations in each
   phase file. Never use `git add -A`. Never amend a prior phase's commit. Never use
   `--no-verify`. Never use interactive git flags (`-i`).
6. **Phase files are the source of truth.** If the file says "Edit `X.swift`" and a surface
   doesn't match what you find in the codebase, read the file, adapt the implementation to the
   spec's intent (not its letter), and keep going. The phase file is a contract on what behavior
   must exist after `NNb`; minor structural details (e.g., which file an enum lives in) can be
   adjusted to fit the codebase as long as the test surfaces are preserved.
7. **Pre-flight before phase 232a:**
   ```bash
   cd ~/Documents/localProject/merlin
   git status                                                                # confirm clean working tree
   git log --oneline -5                                                      # confirm HEAD is at or after phase 231b
   git tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -3                # latest semver tags
   git tag --list v2.0.0                                                     # explicit: v2.0.0 must exist
   ```
   The semver-filtered tag list should end with `v2.0.0`. The repo also carries older
   bare-number tags (`v2`, `v3`, …, `v8`) from the pre-semver era — those are expected and
   not relevant here. If the working tree is dirty *and you did not just commit a v2.1.0
   bootstrap*, or if HEAD is not at/after 231b, or if `v2.0.0` is absent, **stop and report**
   before modifying anything.
8. **Versioning:** Only phase 240b bumps `project.yml`. Never edit `MARKETING_VERSION` or
   `CURRENT_PROJECT_VERSION` in any other phase. After phase 240b, run `xcodegen generate`
   exactly as instructed, then tag `v2.1.0` and create the GitHub release via the `gh` CLI.
9. **Build verification commands.** Use exactly:
   ```bash
   xcodebuild -scheme MerlinTests build-for-testing \
       -destination 'platform=macOS' \
       -derivedDataPath /tmp/merlin-derived 2>&1 \
       | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

   xcodebuild -scheme MerlinTests test \
       -destination 'platform=macOS' \
       -derivedDataPath /tmp/merlin-derived 2>&1 \
       | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
   ```
   Do not invent variants.
10. **Per-phase loop:**
    1. Open the phase file with `cat phases/phase-NN<x>-<name>.md`.
    2. Read its `## Context` block and confirm prerequisites are satisfied.
    3. Implement the listed edits in the listed files.
    4. Run the `## Verify` command. The expected outcome is in the file.
    5. If `BUILD FAILED` and you are on an `a` phase, that is success. If `BUILD SUCCEEDED` and
       all tests pass and you are on a `b` phase, that is success.
    6. If verification does not match the expected outcome, **stop and report** — do not commit
       broken work, do not improvise an unbounded fix loop.
    7. Commit exactly as the phase file specifies.
    8. Append a one-line completion summary to a running buffer (do not write it to a file).
    9. Move to the next phase.
11. **Reporting and stopping conditions.** Report and pause if any of these occur:
    - Verify outcome does not match the phase file's expectation.
    - Any pre-existing test regresses (tests that passed before this work now fail).
    - A `git commit` is rejected by a pre-commit hook. **Fix the underlying issue and make a new
      commit.** Do not amend, do not use `--no-verify`.
    - You discover the working tree contains uncommitted changes you did not make.
    - You encounter an in-progress rebase, merge, or revert.
    - A surface mentioned in a later phase already exists in the codebase (likely a prior partial
      attempt — report so the user can decide whether to keep or reset).
12. **At the end of phase 240b**, after the GitHub release is created, print a one-page summary
    of: every commit hash and message in the sequence, the new version, the tag, the release URL,
    and a copy-pasteable rollback command (`git reset --hard <hash-before-232a>` and
    `gh release delete v2.1.0`).

## What you are shipping (overview, do not paraphrase into commits)

Merlin v2.1.0 makes execution **budget-aware**: every LLM request is sized to fit the active
provider's input window before it is sent. Overflows trigger decomposition (smaller substeps)
first; cross-provider routing to a larger-context model is the last-resort fallback; an
unrecoverable case produces a clean structured stop. The recursive 400-on-overrun recovery
that previously caused infinite loops is **deleted** in phase 237b and replaced with a single
bounded escalation helper. Critic invocation is gated by skill frontmatter, plan-step policy,
and a deterministic verification short-circuit.

Architectural pieces (these *are* the phases, in order):

| Phase | Concern |
|---|---|
| 232 | Telemetry: error body, pre-flight estimate, planner step trace (observability only) |
| 233 | `ProviderBudget` + pre-flight gate + lowered compaction thresholds |
| 234 | Working-set caps (system prompt / RAG / recent turns / tool burst) |
| 235 | Adaptive RAG (chunk count derived from active budget) |
| 236 | Enriched `PlanStep` + `PlannerEngine.refineStep(...)` |
| 237 | `EscalationHandler` + delete recursive recovery + retire retry counters |
| 238 | Critic gating (skill / step / deterministic short-circuit) |
| 239 | Decompose-on-overflow + cross-provider routing as last-resort |
| 240 | Bump to v2.1.0, write `RELEASE-v2.1.0.md`, tag, GitHub release |

## Begin

```bash
cd ~/Documents/localProject/merlin
cat phases/phase-232a-budget-telemetry-tests.md
```

Execute that phase end to end, commit, then advance to `phase-232b-budget-telemetry.md`, and
so on until phase 240b is committed and `v2.1.0` is tagged and released. Stop and report at the
first stopping condition above.
