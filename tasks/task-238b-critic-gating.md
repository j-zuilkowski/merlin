# Task 238b — Critic Gating

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 238a complete: failing tests for the three-input critic gate.

The critic now runs only when there is a reason for it to: a skill says so, a `PlanStep` says
so, or the heuristic has no better answer. Steps whose success can be proven by deterministic
checks (`buildSucceeds`, `testsPass`, `fileExists`, etc.) skip the LLM critic entirely.

---

## Edit

- `Merlin/Skills/SkillFrontmatter.swift` — add `var critic: CriticMode?` field and parse it in
  the existing `parse()` switch at lines ~15–56. Unknown value → emit
  `skill.frontmatter.warning` telemetry and store `nil`.
- `Merlin/Engine/CriticPolicyResolver.swift` — new file. Pure `enum` namespace.
- `Merlin/Engine/CriterionChecker.swift` — new file.
- `Merlin/Engine/CriticEngine.swift` — expose `runStage1(taskType:)` (and the new variant
  `runStage1(criteria:)` taking `[StepCriterion]`) as non-private. Keep `evaluate(...)` as the
  high-level entry point.
- `Merlin/Engine/AgenticEngine.swift`:
    - Replace the `shouldRunCritic` boolean expression at lines ~928–931 with a call to
      `CriticPolicyResolver.resolve(...)` passing: the active `Skill`'s frontmatter, the current
      `PlanStep` (or `nil` if running outside a plan), the existing heuristic tuple, and
      `classifierOverride != nil`.
    - On `.skip` → emit `critic.skipped.policy` and proceed.
    - On `.deterministicOnly` → run `CriterionChecker.check` for each `StepCriterion` on the
      step; if all pass, emit `critic.stage1.short_circuit` and proceed. If any fail, fall
      through to full `critic.evaluate(...)` with the failing criterion as the seed reason.
    - On `.run` → existing `critic.evaluate(...)` call, unchanged.

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

Expected: **BUILD SUCCEEDED** and all task 238a tests pass. Pre-existing critic tests still pass.

## Commit

```bash
git add tasks/task-238b-critic-gating.md \
    Merlin/Skills/SkillFrontmatter.swift \
    Merlin/Engine/CriticPolicyResolver.swift \
    Merlin/Engine/CriterionChecker.swift \
    Merlin/Engine/CriticEngine.swift \
    Merlin/Engine/AgenticEngine.swift
git commit -m "Task 238b — Critic gating (skill frontmatter, step policy, deterministic short-circuit)"
```

## PASTE-LIST update

Append task 238a/238b under the "Budget-Aware Execution (v2.1.0)" section.
