# Codex Orchestration Prompt — Merlin v2.1.0 (Budget-Aware Execution)

Paste this entire prompt into Codex as the first message. Codex will execute  tasks 232–240
in strict sequence, committing after each one.

---

You are executing the Merlin **Budget-Aware Execution** overhaul, which ships as **v2.1.0**.
The work is broken into 18 task files (nine NNa/NNb pairs covering  tasks 232 through 240) under
`tasks/`. Each task file is **self-contained** and includes its own context, surface list,
verify command, and commit instructions.

## Hard rules — read and obey before starting

1. **Working directory:** `~/Documents/localProject/merlin`. All commands run from there.
2. **Read `constitution.md` and `spec.md` first.** They define the project's TDD discipline,
   Swift standards, build commands, versioning policy, and constraints (Swift 5.10, macOS 14+,
   non-sandboxed, no third-party packages, `SWIFT_STRICT_CONCURRENCY=complete`, zero warnings,
   zero errors). Honor every rule. Do not relax `SWIFT_STRICT_CONCURRENCY`. The "V2.1 —
   Budget-Aware Execution" section in `spec.md` is the architectural spec for this work
   —  tasks must match it, not modify it.
3. **Strict task order.** Execute  tasks in this exact sequence — no reordering, no skipping,
   no merging:
   ```
   232a → 232b → 233a → 233b → 234a → 234b → 235a → 235b →
   236a → 236b → 237a → 237b → 238a → 238b → 239a → 239b →
   240a → 240b
   ```
4. **TDD discipline is non-negotiable.** Every `NNa` task **must** end with a `BUILD FAILED`
   verification (the tests are deliberately failing because the surfaces don't yet exist) and a
   git commit of just those failing tests. Every `NNb` task **must** end with `BUILD SUCCEEDED`
   and a passing test run before the commit. **Never** skip the failing-tests commit. **Never**
   batch commits across  tasks.
5. **Commit after every task.** Use the exact `git add` and `git commit` invocations in each
   task file. Never use `git add -A`. Never amend a prior task's commit. Never use
   `--no-verify`. Never use interactive git flags (`-i`).
6. **Task files are the source of truth.** If the file says "Edit `X.swift`" and a surface
   doesn't match what you find in the codebase, read the file, adapt the implementation to the
   spec's intent (not its letter), and keep going. The task file is a contract on what behavior
   must exist after `NNb`; minor structural details (e.g., which file an enum lives in) can be
   adjusted to fit the codebase as long as the test surfaces are preserved.
7. **Pre-flight before task 232a:**
   ```bash
   cd ~/Documents/localProject/merlin
   git status --short                                                        # only modified-tracked lines block
   git diff --quiet && git diff --cached --quiet && echo "clean" || echo "dirty"
   git log --oneline -5                                                      # confirm HEAD is at or after the v2.1.0 scaffolding commit (or 231b)
   git tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -3                # latest semver tags — should end with v2.0.0
   git tag --list v2.0.0                                                     # explicit: v2.0.0 must exist
   ```
   **Blocking conditions** (stop and report if any are true):
   - The `git diff` check above prints `dirty` (any modified or staged tracked files).
   - HEAD is not at or after `f667ce5` (Task 231b) — should be at the v2.1.0 scaffolding
     commit `137c726` or later.
   - `v2.0.0` is missing from the tag list.

   **Non-blocking** (proceed normally):
   - Untracked files in `git status --short` (lines beginning with `??`). The repo carries
     `memory/` as an untracked working directory; ignore it.
   - The semver tag list contains intermediate tags after `v2.0.0` (any patch releases that
     landed between the scaffolding and your run). The repo also carries older bare-number
     tags (`v2`, `v3`, …, `v8`) from the pre-semver era — expected, not relevant here.
8. **Versioning:** Only task 240b bumps `project.yml`. Never edit `MARKETING_VERSION` or
   `CURRENT_PROJECT_VERSION` in any other task. After task 240b, run `xcodegen generate`
   exactly as instructed, then tag `v2.1.0` and create the GitHub release via the `gh` CLI.
9. **Build verification commands.** Use exactly:
   ```bash
   xcodebuild -scheme MerlinTests build-for-testing \
       -destination 'platform=macOS' \
       -derivedDataPath /tmp/merlin-derived \
       CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
       | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

   xcodebuild -scheme MerlinTests test \
       -destination 'platform=macOS' \
       -derivedDataPath /tmp/merlin-derived \
       CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
       | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
   ```
   Do not invent variants. The three `CODE_SIGN_*` overrides are required in this sandbox because
   the "Merlin Dev Signing" certificate is not available here. **Every** xcodebuild invocation in
   every task file already includes them; do not omit them.
10. **Per-task loop:**
    1. Open the task file with `cat tasks/task-NN<x>-<name>.md`.
    2. Read its `## Context` block and confirm prerequisites are satisfied.
    3. Implement the listed edits in the listed files.
    4. Run the `## Verify` command. The expected outcome is in the file.
    5. If `BUILD FAILED` and you are on an `a` task, that is success. If `BUILD SUCCEEDED` and
       all tests pass and you are on a `b` task, that is success.
    6. If verification does not match the expected outcome, **stop and report** — do not commit
       broken work, do not improvise an unbounded fix loop.
    7. Commit exactly as the task file specifies.
    8. Append a one-line completion summary to a running buffer (do not write it to a file).
    9. Move to the next task.
11. **Reporting and stopping conditions.** Report and pause if any of these occur:
    - Verify outcome does not match the task file's expectation.
    - Any pre-existing test regresses (tests that passed before this work now fail).
    - A `git commit` is rejected by a pre-commit hook. **Fix the underlying issue and make a new
      commit.** Do not amend, do not use `--no-verify`.
    - You discover the working tree contains uncommitted changes you did not make.
    - You encounter an in-progress rebase, merge, or revert.
    - A surface mentioned in a later task already exists in the codebase (likely a prior partial
      attempt — report so the user can decide whether to keep or reset).
12. **At the end of task 240b**, after the GitHub release is created, print a one-page summary
    of: every commit hash and message in the sequence, the new version, the tag, the release URL,
    and a copy-pasteable rollback command (`git reset --hard <hash-before-232a>` and
    `gh release delete v2.1.0`).

## What you are shipping (overview, do not paraphrase into commits)

Merlin v2.1.0 makes execution **budget-aware**: every LLM request is sized to fit the active
provider's input window before it is sent. Overflows trigger decomposition (smaller substeps)
first; cross-provider routing to a larger-context model is the last-resort fallback; an
unrecoverable case produces a clean structured stop. The recursive 400-on-overrun recovery
that previously caused infinite loops is **deleted** in task 237b and replaced with a single
bounded escalation helper. Critic invocation is gated by skill frontmatter, plan-step policy,
and a deterministic verification short-circuit.

Architectural pieces (these *are* the  tasks, in order):

| Task | Concern |
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
cat tasks/task-232a-budget-telemetry-tests.md
```

Execute that task end to end, commit, then advance to `task-232b-budget-telemetry.md`, and
so on until task 240b is committed and `v2.1.0` is tagged and released. Stop and report at the
first stopping condition above.
