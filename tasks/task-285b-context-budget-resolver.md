# Task 285b — Context Budget Resolver

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 285a complete: failing tests for `ContextBudgetResolver` / `ContextBudgetStore`.

After this task the per-request budget is **discovered** from the active provider and
model, not read from a hardcoded `ProviderConfig.budget` default. Discovery has two
tiers, backed by one durable store:

  - **Queryable providers** (local runners, OpenRouter) expose the real context window
    over HTTP — the resolver queries it live.
  - **Non-queryable providers** (OpenAI / Anthropic / DeepSeek) expose no such field. The
    resolver starts conservative and **learns** the real window from the first
    context-overflow 400, then persists it.
  - **The durable store is `ProviderConfig.budget` in `providers.json`** — the same field
    and file a manually-entered budget uses. A learned limit is written exactly where a
    typed one would go, so it survives restarts with no separate machine-only store and
    the same 400 is never paid twice.

This is what makes budget enforcement correct on any model/provider — especially local
runners, where the context window depends entirely on how the model was loaded — with
zero user configuration.

---

## Edit

### 1. New file — `Merlin/Engine/ContextBudgetResolver.swift`

Implement `ContextBudgetStore`, `EphemeralBudgetStore`, `PersistedProviderBudgetStore`,
and the `ContextBudgetResolver` actor from the 285a surface block.

**`ContextBudgetStore`** (top-level protocol — Swift forbids nesting a protocol in a type):

```swift
/// Reads/writes the durable per-provider context window. The production
/// implementation is backed by `ProviderConfig.budget` in `providers.json` — the
/// same field a manually entered budget uses.
protocol ContextBudgetStore: Sendable {
    func persistedContextTokens(for providerID: String) async -> Int?
    func persist(contextTokens: Int, for providerID: String) async
}

/// No-op store: returns nil, ignores writes. Default for callers/tests that do not
/// need persistence.
struct EphemeralBudgetStore: ContextBudgetStore {
    func persistedContextTokens(for providerID: String) async -> Int? { nil }
    func persist(contextTokens: Int, for providerID: String) async {}
}
```

**`ContextBudgetResolver`** — the actor:

- `usableInputTokens(for:)` — return a cached value when present and within `ttl`;
  otherwise resolve, in this order:
  1. `source(provider)` — live discovery. Non-nil wins. **Write the discovered value
     through to `store.persist(...)`** so `providers.json` stays current for the next
     launch.
  2. `store.persistedContextTokens(for: provider.id)` — the durable learned/typed value.
  3. `conservativeContextTokens` — last-resort fallback.
  Then compute `max(floor, resolvedContextWindow - reservedOutputTokens)` (`floor`
  ≈ 2 000), cache it keyed by `provider.id` for `ttl`, and return it. (`provider.id`
  encodes the model for virtual IDs, so two models on the same runner resolve
  independently.) When `ttl == 0`, never serve from cache — always re-resolve.

- `recordObservedLimit(contextTokens:for:)` — called by `PreflightGuard` (task 286b)
  when a provider rejects a request with a context-overflow 400. Persist the learned
  window via `store.persist(contextTokens:for: provider.id)` and refresh the in-memory
  cache entry so the *current* session also stops over-sending immediately. This is the
  conservative-start / learn-from-400 / never-pay-it-twice loop.

- `static let shared` — built with `PersistedProviderBudgetStore()` and the production
  `source` (below), for callers that do not inject their own.

**Store-key note.** `store` keys on `provider.id`. For virtual local IDs
(`"lmstudio:phi-4"`) the production store maps to the base provider's config
(strip at the first `:`). Local runners are always resolved live by `source`, so their
persisted value is only a freshness cache. The learn-from-400 persistence is
load-bearing for the three non-queryable commercial providers, whose IDs are plain
(`"deepseek"`) and whose `ProviderConfig` carries exactly one model — so a per-provider
budget is per-model-accurate there.

**Production `source`** — the default initialiser supplies a source that discovers the
real context window:
  - **Local runner provider** (id maps to a `LocalModelManagerProtocol`, or `isLocal`):
    query the runner for the *loaded* model's context window. For LM Studio reuse the
    `/api/v0/models` fetch already in `LMStudioModelManager.ensureContextLength()` —
    extract that into a reusable `loadedContextLength()`-style call and use its
    `loaded_context_length`. For other runners, use their equivalent (Ollama `/api/show`).
  - **OpenRouter**: query `/api/v1/models` and read `context_length` for
    `provider.resolvedModelID`.
  - **OpenAI / Anthropic / DeepSeek**: return nil — no API field exposes this. The
    resolver falls through to the persisted store (a previously learned 400 value) or
    the conservative fallback. Do **not** ship a hardcoded model→size map; the 400 is
    the authority and `recordObservedLimit` captures it.
  - Discovery must be best-effort and non-throwing — any failure returns nil.

**`PersistedProviderBudgetStore`** — the production `ContextBudgetStore`, backed by
`providers.json`:

```swift
struct PersistedProviderBudgetStore: ContextBudgetStore {
    func persistedContextTokens(for providerID: String) async -> Int? {
        ProviderRegistry.persistedBudget(for: baseID(providerID))?.maxInputTokens
    }
    func persist(contextTokens: Int, for providerID: String) async {
        ProviderRegistry.recordLearnedContextWindow(contextTokens, for: baseID(providerID))
    }
    // baseID: strip at first ":" so "lmstudio:phi-4" → "lmstudio".
}
```

- Emit `engine.budget.resolved` telemetry (`provider_id`, `discovered`, `usable`,
  `source: "runner" | "openrouter" | "store" | "fallback"`) on each resolve, and
  `engine.budget.learned` (`provider_id`, `context_tokens`) when `recordObservedLimit`
  persists a value — so both the resolved budget and the learning event are observable.

### 2. `Merlin/Providers/ProviderConfig.swift` — persistence helpers on `ProviderRegistry`

`providers.json` (the `Snapshot` written by `persist()`) is already the home of
`ProviderConfig.budget`. Add the read/write surface the resolver's store needs, mirroring
the existing `updateMaxOutputTokens(_:for:)` / static `persistedEnabledProviders()`:

- Instance `func updateBudget(_ budget: ProviderBudget?, for id: String)` — sets
  `providers[index].budget` and calls `persist()`. This is the **manual / UI** entry
  point: it is exactly the path a user-typed budget would take.

- `nonisolated static func persistedBudget(for id: String) -> ProviderBudget?` — loads
  the `Snapshot` from `defaultPersistURL` and returns that provider's `.budget`.

- `nonisolated static func recordLearnedContextWindow(_ contextTokens: Int, for id: String)`
  — loads the `Snapshot`, sets that provider's `.budget` to
  `ProviderBudget(maxInputTokens: contextTokens, reservedOutputTokens: existingReserved)`
  (keep any existing `reservedOutputTokens`, else default 4 096), and writes the
  `Snapshot` back atomically. This is the **learned** entry point; it lands in the same
  `budget` field and file as `updateBudget`, so a learned window and a typed one are
  indistinguishable and both survive restart.

These two statics are `nonisolated` (pure file I/O) so the `ContextBudgetResolver` actor
can call them without a `@MainActor` hop. A live in-memory `ProviderRegistry` will pick
up an externally-written value on next launch; the resolver's own cache covers the
current session.

`ProviderConfig.budget` is **promoted, not removed**: it was a static guess, it is now
the durable learned/typed store the resolver reads and writes. The hardcoded `budget:`
values in `defaultProviders` remain only as the conservative seed before anything is
learned.

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

Expected: **BUILD SUCCEEDED**, all task 285a tests pass, no prior task regresses.

## Commit

```bash
git add tasks/task-285b-context-budget-resolver.md \
    Merlin/Engine/ContextBudgetResolver.swift \
    Merlin/Providers/ProviderConfig.swift \
    Merlin/Providers/LocalModelManager/LMStudioModelManager.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 285b — ContextBudgetResolver: discover and persist the model's real context window"
```

(Include `LMStudioModelManager.swift` only if the `loaded_context_length` fetch was
extracted into a reusable call there.)

## Fixes

The request budget is now discovered from the provider/runner — the loaded model's
actual context window — instead of a hardcoded per-provider guess. A local model loaded
at 4 096 context is budgeted at 4 096, not 32 000. For commercial providers that expose
no context-size field, the resolver starts conservative and learns the real window from
the first context-overflow 400, **persisting it to `ProviderConfig.budget` in
`providers.json`** — the same field a manually-entered budget uses — so the value
survives restarts and the 400 is never paid twice. Task 286's universal guard consumes
this resolver (and feeds `recordObservedLimit` on a 400), so enforcement is correct on
every model and provider with no user configuration.

### Fix (2026-05-19) — reject a degenerate learned context window

`ProviderRegistry.recordLearnedContextWindow(_:for:)` persisted whatever context-token
count it was handed, with no lower bound. LM Studio's `/api/v0/models` reports
`loaded_context_length: 0` for a model that is registered but not yet fully loaded, so a
discovery call that landed during model load wrote `ProviderBudget(maxInputTokens: 0,
reservedOutputTokens: 4_096)` — `usableInputTokens` of −4 096 — into `providers.json`.
Every later run then read that degenerate budget and died at its first preflight check
(`preflight overflow (5642 > 0)`), which is why S1 failed intermittently with `tools 0`.

`recordLearnedContextWindow` now builds the candidate `ProviderBudget` and persists it
only when `usableInputTokens > 0`; a non-positive observation is dropped, leaving the
existing persisted budget intact. This is the persistence-path root-cause fix that
commit `802a419` (the `ProviderBudget.preflightSafe` read-side clamp) flagged for
separate root-causing — the two together close the bug at both the write and read
boundaries.

`recordLearnedContextWindow(_:for:persistURL:)` and `persistedBudget(for:persistURL:)`
overloads were added as test seams so the persistence path can be verified
deterministically against a temp file (`ProviderRegistryTests`); the no-`persistURL`
forms delegate to them with `defaultPersistURL`.
