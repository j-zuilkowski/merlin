# Release v2.1.0 - Budget-Aware Execution

## Summary
Budget-Aware Execution. Merlin now sizes every request to the active provider's input window,
decomposes oversized work, and stops cleanly on unrecoverable overflow. Works regardless of
provider/model/context.

## What's new
- Per-provider `ProviderBudget` registered as configuration data.
- Pre-flight estimator gates every LLM call.
- Working-set caps for system prompt, RAG, recent turns, and tool bursts.
- Adaptive RAG injection sized to the active budget.
- Enriched `PlanStep` with token budget, success criteria, critic mode, and minimum context.
- `PlannerEngine.refineStep(...)` as the single decomposition entry point.
- `EscalationHandler` as the single bounded retry and escalation policy. No recursion anywhere.
- Critic gating by skill frontmatter, per-step policy, and deterministic short-circuit.
- Decompose-first overflow handling with cross-provider routing as the last-resort fallback.
- New telemetry: `engine.preflight.*`, `engine.escalation.*`, `planner.refine.*`,
  `engine.rag.selected`, `critic.stage1.short_circuit`.

## Internal changes
- `PlanStep.successCriteria` now uses `[StepCriterion]`. The decoder still accepts the legacy
  single-string form, so existing serialized plans continue to load.
- `AgenticEngine` no longer uses `contextLengthRetryCount`, `maxContextOverrunRecoveryAttempts`,
  or `contextOverrunRecoveryDirective`. Recovery now flows through `EscalationHandler`.
- New `.cleanStop` case on `AgentEvent`. Existing UI consumers can keep falling through to the
  `.systemNote` rendering path until a dedicated affordance ships.

## Migration
- Existing skills without `critic:` frontmatter continue to use the heuristic unchanged.
- Existing config without `ProviderBudget` falls through to the conservative default
  `(maxInputTokens: 32_000, reservedOutputTokens: 4_096)`.
- No user data migration is required.
