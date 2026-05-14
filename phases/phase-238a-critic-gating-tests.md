# Phase 238a — Critic Gating Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 237b complete: EscalationHandler installed, recursive recovery deleted.

Today the critic fires on a hard-coded heuristic at `AgenticEngine.swift:928–931`. This phase
replaces that with a three-input gate: skill frontmatter `critic:`, current `PlanStep.requiresCritic`,
and Stage-1 deterministic verification short-circuit (skip the LLM critic when the structured
`StepCriterion` checks already prove the step succeeded).

New surface introduced in phase 238b:
  - `SkillFrontmatter.critic: CriticMode?` — parsed from the YAML `critic:` field. Legal values
    `required`, `optional`, `skip`. Absent → `nil` (defer to step/heuristic).
  - `CriticPolicyResolver` in `Merlin/Engine/CriticPolicyResolver.swift`:
    ```swift
    enum CriticDecision: Sendable { case run, skip, deterministicOnly }
    enum CriticPolicyResolver {
        static func resolve(skill: SkillFrontmatter?, step: PlanStep?,
                            heuristic: (writtenFiles: Bool, substantial: Bool, complexity: ComplexityTier),
                            classifierOverride: Bool) -> CriticDecision
    }
    ```
    Precedence (high → low): skill `.skip` → skip; skill `.required` → run;
    step `.skip` → skip; step `.required` → run; deterministic verification passes
    (`StepCriterion` checks all green) → `.deterministicOnly`; heuristic → run when any heuristic
    flag true, else skip.
  - `CriticEngine.runStage1(taskType:)` already exists — exposed publicly so the executor can
    invoke it independently of `evaluate`. If all `StepCriterion`s for the current step are
    `buildSucceeds` / `testsPass` / `fileExists` / `regexMatch` / `shellExitZero` (i.e.
    non-`prose`) and all pass, return `.pass` without calling Stage 2.
  - `CriterionChecker` in `Merlin/Engine/CriterionChecker.swift`:
    ```swift
    actor CriterionChecker {
        init(shellRunner: any ShellRunning)
        func check(_ criterion: StepCriterion) async -> Bool
    }
    ```
    Maps `buildSucceeds` → existing `xcodebuild` invocation via `ShellRunning`; `testsPass(scheme:)` →
    test invocation; `fileExists(path:)` → `FileManager`; `regexMatch(pattern:in:)` → in-process
    regex on shell output or file; `shellExitZero(command:)` → `ShellRunning.run`. `prose(_)`
    always returns `false` (cannot be auto-checked; falls through to LLM critic).
  - `AgenticEngine.swift:928–984` block rewritten to consult `CriticPolicyResolver` and
    `CriterionChecker` before falling through to the existing `critic.evaluate(...)` call.

TDD coverage:
  File 1 — `MerlinTests/Unit/SkillFrontmatterCriticTests.swift`: `critic: required` /
    `critic: skip` / `critic: optional` parse correctly; absent field → `nil`; invalid value
    → `nil` with a parse-warning telemetry event.
  File 2 — `MerlinTests/Unit/CriticPolicyResolverTests.swift`: exhaustive precedence matrix.
    Skill > step > deterministic > heuristic. `classifierOverride` forces `.run` unless skill
    explicitly says `.skip`.
  File 3 — `MerlinTests/Unit/CriterionCheckerTests.swift`: each criterion case maps to the
    expected check; `prose` always returns `false`; `fileExists(path:)` uses `FileManager`
    rather than shelling out.
  File 4 — `MerlinTests/Unit/DeterministicVerificationShortCircuitTests.swift`: when a
    `PlanStep` carries only non-`prose` criteria and all check `true`, the engine emits exactly
    one `critic.stage1.short_circuit` event and does *not* invoke the reason provider for
    Stage 2.

---

## Edit

- `MerlinTests/Unit/SkillFrontmatterCriticTests.swift`
- `MerlinTests/Unit/CriticPolicyResolverTests.swift`
- `MerlinTests/Unit/CriterionCheckerTests.swift`
- `MerlinTests/Unit/DeterministicVerificationShortCircuitTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `SkillFrontmatter.critic`, `CriticPolicyResolver`,
`CriterionChecker`, and the missing `critic.stage1.short_circuit` telemetry path.

## Commit

```bash
git add phases/phase-238a-critic-gating-tests.md \
    MerlinTests/Unit/SkillFrontmatterCriticTests.swift \
    MerlinTests/Unit/CriticPolicyResolverTests.swift \
    MerlinTests/Unit/CriterionCheckerTests.swift \
    MerlinTests/Unit/DeterministicVerificationShortCircuitTests.swift
git commit -m "Phase 238a — CriticGatingTests (failing)"
```
