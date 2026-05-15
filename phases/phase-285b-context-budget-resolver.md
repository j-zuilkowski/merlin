# Phase 285b — Context Budget Resolver

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 285a complete: failing tests for `ContextBudgetResolver`.

After this phase the per-request budget is **discovered** from the active provider and
model, not read from a hardcoded `ProviderConfig.budget`. This is what makes budget
enforcement correct on any model/provider — especially local runners, where the context
window depends entirely on how the model was loaded.

---

## Edit — `Merlin/Engine/ContextBudgetResolver.swift` (new file)

Implement the `ContextBudgetResolver` actor from the 285a surface block:

- `usableInputTokens(for:)` — return a cached value when present and within `ttl`;
  otherwise call `source(provider)`, compute
  `max(floor, (discovered ?? conservativeContextTokens) - reservedOutputTokens)`,
  cache it keyed by `provider.id` (the id encodes the model for virtual IDs, so two
  models on the same runner resolve independently), and return it. `floor` ≈ 2 000.

- **Production `source`** — the default initialiser supplies a source that discovers the
  real context window:
  - **Local runner provider** (id maps to a `LocalModelManagerProtocol`, or `isLocal`):
    query the runner for the *loaded* model's context window. For LM Studio reuse the
    `/api/v0/models` fetch already in `LMStudioModelManager.ensureContextLength()` —
    extract that into a reusable `loadedContextLength()`-style call and use its
    `loaded_context_length`. For other runners, use their equivalent (Ollama `/api/show`);
    if a runner exposes nothing, return nil (→ conservative fallback).
  - **Remote provider**: a model-keyed context-window lookup (e.g. DeepSeek / OpenAI /
    Anthropic families). Keep it a small internal map keyed by `provider.resolvedModelID`;
    unknown model → nil (→ conservative fallback). Do not block on a network call here.
  - Discovery must be best-effort and non-throwing — any failure returns nil.

- Expose a `static let shared` built with the production source, for callers that do not
  inject their own.

- Emit `engine.budget.resolved` telemetry (`provider_id`, `discovered`, `usable`,
  `source: "runner" | "model_map" | "fallback"`) so the resolved budget is observable.

`ProviderConfig.budget` is **not removed** — it remains as a last-resort hint if a caller
wants it — but the resolver, not that static field, is now the authority. (A later phase
may drop `ProviderConfig.budget` entirely once nothing reads it.)

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

Expected: **BUILD SUCCEEDED**, all phase 285a tests pass, no prior phase regresses.

## Commit

```bash
git add phases/phase-285b-context-budget-resolver.md \
    Merlin/Engine/ContextBudgetResolver.swift \
    Merlin/Providers/LocalModelManager/LMStudioModelManager.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 285b — ContextBudgetResolver: discover the model's real context window"
```

(Include `LMStudioModelManager.swift` only if the `loaded_context_length` fetch was
extracted into a reusable call there.)

## Fixes

The request budget is now discovered from the provider/runner — the loaded model's
actual context window — instead of a hardcoded per-provider guess. A local model loaded
at 4 096 context is budgeted at 4 096, not 32 000. Phase 286's universal guard consumes
this resolver, so enforcement is correct on every model and provider with no user
configuration.
