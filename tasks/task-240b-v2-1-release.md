# Task 240b — v2.1.0 Release

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 240a complete: failing version + release-notes tests are in place.

This task ships v2.1.0 — Budget-Aware Execution. Follow `spec.md` § Versioning Policy
step-by-step. **Do not skip** the `xcodegen generate` step or the GitHub release step.

---

## Edit

- `project.yml`:
    - `MARKETING_VERSION: "2.0.0"` → `MARKETING_VERSION: "2.1.0"`.
    - `CURRENT_PROJECT_VERSION: 15` → `CURRENT_PROJECT_VERSION: 16`.
- `constitution.md`:
    - "Current version: 2.0.0 (build 15, tag v2.0.0)" → "Current version: 2.1.0 (build 16, tag v2.1.0)".
- `RELEASE-v2.1.0.md` — new file at repo root. Required sections:
    - `## Summary` — one paragraph: "Budget-Aware Execution. Merlin now sizes every request to
      the active provider's input window, decomposes oversized work, and stops cleanly on
      unrecoverable overflow. Works regardless of provider/model/context."
    - `## What's new`:
        - Per-provider `ProviderBudget` registered as configuration data.
        - Pre-flight estimator gates every LLM call.
        - Working-set caps for system prompt, RAG, recent turns, and tool bursts.
        - Adaptive RAG injection sized to the active budget.
        - Enriched `PlanStep` (token budget, success criteria, critic mode, min context).
        - `PlannerEngine.refineStep(...)` — single decomposition entry point.
        - `EscalationHandler` — single bounded retry/escalation policy. No recursion anywhere.
        - Critic gating by skill frontmatter, per-step policy, and deterministic short-circuit.
        - Decompose-first overflow handling with cross-provider routing as last-resort fallback.
        - New telemetry: `engine.preflight.*`, `engine.escalation.*`, `planner.refine.*`,
          `engine.rag.selected`, `critic.stage1.short_circuit`.
    - `## Internal changes` (no external consumers affected):
        - `PlanStep.successCriteria` changed from `String` to `[StepCriterion]`. Decoder accepts
          the legacy single-string form via wrapping; existing serialized plans continue to load.
        - `AgenticEngine` removed: `contextLengthRetryCount`, `maxContextOverrunRecoveryAttempts`,
          `contextOverrunRecoveryDirective`. Recovery is now via `EscalationHandler`. These were
          internal members with no external consumers.
        - New `.cleanStop` case on `AgentEvent`. UI consumers fall through to `.systemNote`
          rendering until a distinct UI affordance ships.
    - `## Migration`:
        - Existing skills with no `critic:` frontmatter field continue to use the heuristic
          unchanged.
        - Existing config without `ProviderBudget` falls through to the conservative default
          `(maxInputTokens: 32_000, reservedOutputTokens: 4_096)`.
        - No user data migration required.
- **Do not modify `spec.md`.** The "V2.1 — Budget-Aware Execution" section was written
  before this task series began and is the architectural source of truth. The `## Versioning
  Policy` section it references is unchanged.
- After all edits, run:
    ```bash
    cd ~/Documents/localProject/merlin
    xcodegen generate
    xcodebuild -scheme MerlinTests test \
        -destination 'platform=macOS' \
        -derivedDataPath /tmp/merlin-derived \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
    ```
    Confirm tests pass, then proceed to commit/tag/release.

---

## Verify

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

Expected: **BUILD SUCCEEDED** and **all task 240a tests pass** (version is now 2.1.0, release
notes file exists).

Then build a Release archive and launch from `build/Debug/Merlin.app`; manually confirm
"About Merlin" reads `Version 2.1.0 (16)`.

## Commit, tag, release

```bash
cd ~/Documents/localProject/merlin

git add tasks/task-240b-v2-1-release.md \
    project.yml \
    constitution.md \
    RELEASE-v2.1.0.md \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 240b — Bump version to 2.1.0 (Budget-Aware Execution)"

git tag v2.1.0
git push
git push --tags

gh release create v2.1.0 \
    --repo j-zuilkowski/merlin \
    --title "v2.1.0 — Budget-Aware Execution" \
    --notes-file RELEASE-v2.1.0.md \
    --latest
```

## PASTE-LIST update

Append task 240a/240b under the "Budget-Aware Execution (v2.1.0)" section. Mark the section
**RELEASED** with the tag `v2.1.0`.
