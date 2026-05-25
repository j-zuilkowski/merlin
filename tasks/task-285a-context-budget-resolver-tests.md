# Phase 285a — Context Budget Resolver Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 284 complete: tool output is capped.

**The problem.** The budget a request is sized against comes from `ProviderConfig.budget`
— a value hardcoded per provider (`deepseek` 65 536, `.conservative` 32 000). That is a
static guess and it is wrong precisely for local runners: an LM Studio model can be
loaded at 4 096 / 8 192 / 32 768 context depending on how the user loaded it. A
hardcoded 32 000 budget would let an 8×-oversized request through and still get an
HTTP 400. The budget must be **discovered from the provider/runner**, not configured.

The runner already reports it — `LMStudioModelManager.ensureContextLength()` queries
LM Studio's `/api/v0/models` for `loaded_context_length` — that fetch is just never
connected to the budget.

**Two discovery tiers, one durable store.** Local runners and OpenRouter expose the real
context window over HTTP and can be queried live. OpenAI / Anthropic / DeepSeek expose
no such field — for those the only reliable signal is the **context-overflow 400 itself**
("maximum context length is 8192 tokens"). So the resolver starts conservative and, when
a 400 reveals the real number, **persists it** so the same 400 is never paid twice. The
persisted value is written to `ProviderConfig.budget` in `providers.json` — the exact
field and file a manually-entered budget uses — so a learned limit is indistinguishable
from a typed one and survives app restarts with no separate machine-only store.

New surface introduced in phase 285b:
  - `ContextBudgetStore` protocol — reads/writes the durable per-provider context
    window. Injectable so tests are deterministic; the production implementation is
    backed by `ProviderConfig.budget` in `providers.json`.
    ```swift
    protocol ContextBudgetStore: Sendable {
        /// The persisted context-window size (tokens) for `providerID`, or nil.
        func persistedContextTokens(for providerID: String) async -> Int?
        /// Persist `contextTokens` as the provider's context window.
        func persist(contextTokens: Int, for providerID: String) async
    }
    ```
  - `ContextBudgetResolver` actor in `Merlin/Engine/ContextBudgetResolver.swift`:
    ```swift
    actor ContextBudgetResolver {
        /// `source` discovers the raw context-window size (tokens) for a provider
        /// live (local runner / OpenRouter), or nil when it cannot. `store` is the
        /// durable fallback/learned-value layer (→ providers.json). Both injectable
        /// so tests are deterministic; the production initialiser wires the real ones.
        init(reservedOutputTokens: Int = 4_096,
             conservativeContextTokens: Int = 32_000,
             ttl: TimeInterval = 300,
             store: any ContextBudgetStore = EphemeralBudgetStore(),
             source: @escaping @Sendable (any LLMProvider) async -> Int?)

        /// Usable input-token budget for `provider`: resolved context window minus
        /// reserved output, floored at a safe minimum. Cached per `provider.id` for
        /// `ttl`. Resolution order: live `source` → persisted `store` → conservative.
        func usableInputTokens(for provider: any LLMProvider) async -> Int

        /// Records a context window learned from a provider 400. Persists it via the
        /// store (→ providers.json) so the same 400 is never paid twice, and refreshes
        /// the in-memory cache. Called by `PreflightGuard` (phase 286b) when
        /// `ProviderError.isContextLengthExceeded` fires.
        func recordObservedLimit(contextTokens: Int, for provider: any LLMProvider) async
    }
    ```
  - `EphemeralBudgetStore` — a no-op `ContextBudgetStore` (returns nil, ignores writes),
    the default for callers/tests that do not care about persistence.

TDD coverage:
  File 1 — `MerlinTests/Unit/ContextBudgetResolverTests.swift`: a live `source` that
    reports a context size yields `size − reservedOutput`; a `source` that returns nil
    falls through to the persisted `store`, and to the conservative fallback when the
    store is also empty; the result is never below a floor; the source is consulted once
    per provider within the TTL (caching); `recordObservedLimit` persists the learned
    window to the store and that value is used after the cache expires; a live discovery
    is also written through to the store so `providers.json` stays current.

---

## Write to: MerlinTests/Unit/ContextBudgetResolverTests.swift

```swift
import XCTest
@testable import Merlin

final class ContextBudgetResolverTests: XCTestCase {

    private struct StubProvider: LLMProvider, @unchecked Sendable {
        let id: String
        let baseURL = URL(string: "http://localhost:1234")!
        func complete(request: CompletionRequest)
            async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    /// An in-memory `ContextBudgetStore` that records the last write — lets a test
    /// assert both that persistence happened and that the persisted value is reused.
    private actor RecordingBudgetStore: ContextBudgetStore {
        private var byID: [String: Int]
        private(set) var lastPersisted: Int?

        init(seed: [String: Int] = [:]) { byID = seed }

        func persistedContextTokens(for providerID: String) async -> Int? {
            byID[providerID]
        }
        func persist(contextTokens: Int, for providerID: String) async {
            byID[providerID] = contextTokens
            lastPersisted = contextTokens
        }
    }

    func testDiscoveredContextYieldsContextMinusReservedOutput() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in 8_192 })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 8_192 - 4_096)
    }

    func testNilDiscoveryAndEmptyStoreFallsBackToConservative() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in nil })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 32_000 - 4_096)
    }

    func testPersistedStoreUsedWhenLiveDiscoveryReturnsNil() async {
        // OpenAI/Anthropic/DeepSeek cannot be queried live (source → nil); a value
        // previously persisted to providers.json must be honoured over the fallback.
        let store = RecordingBudgetStore(seed: ["deepseek": 16_384])
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             store: store,
                                             source: { _ in nil })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "deepseek"))
        XCTAssertEqual(budget, 16_384 - 4_096,
            "a persisted context window must win over the conservative fallback")
    }

    func testBudgetNeverGoesBelowAFloor() async {
        // A tiny reported context must not produce a zero or negative budget.
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in 2_048 })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:tiny"))
        XCTAssertGreaterThan(budget, 0,
            "a small context window must still yield a positive usable budget")
    }

    func testSourceIsConsultedOncePerProviderWithinTTL() async {
        let counter = CallCounter()
        let resolver = ContextBudgetResolver(
            ttl: 300,
            source: { _ in await counter.bump(); return 8_192 })
        let p = StubProvider(id: "lmstudio:m")
        _ = await resolver.usableInputTokens(for: p)
        _ = await resolver.usableInputTokens(for: p)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "discovery must be cached within the TTL")
    }

    func testRecordedLimitIsPersistedAndSurvivesCacheExpiry() async {
        // ttl 0 → the in-memory cache is always stale, so the second resolve must come
        // from the persisted store. This is the conservative-start / learn-from-400 /
        // never-pay-it-twice path for commercial providers.
        let store = RecordingBudgetStore()
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             ttl: 0,
                                             store: store,
                                             source: { _ in nil })
        let p = StubProvider(id: "deepseek")

        let before = await resolver.usableInputTokens(for: p)
        XCTAssertEqual(before, 32_000 - 4_096, "starts conservative before any 400")

        await resolver.recordObservedLimit(contextTokens: 8_192, for: p)

        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted, 8_192,
            "a learned limit must be written through to the durable store")

        let after = await resolver.usableInputTokens(for: p)
        XCTAssertEqual(after, 8_192 - 4_096,
            "after learning, the resolved budget must reflect the persisted window")
    }

    func testLiveDiscoveryIsWrittenThroughToTheStore() async {
        // A queryable runner's live value should also be persisted, so providers.json
        // stays current and a later launch has a good starting point.
        let store = RecordingBudgetStore()
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             store: store,
                                             source: { _ in 8_192 })
        _ = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted, 8_192,
            "a live-discovered context window must be written through to the store")
    }

    private actor CallCounter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
```

(If `LLMProvider` requires more members, mirror the stub providers in
`MerlinTests/Unit/PreflightGateTests.swift` / `PreflightCapsIntegrationTests.swift`.)

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — errors naming the missing `ContextBudgetResolver`,
`ContextBudgetStore`, and `EphemeralBudgetStore`.

## Commit

```bash
git add tasks/task-285a-context-budget-resolver-tests.md \
    MerlinTests/Unit/ContextBudgetResolverTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 285a — ContextBudgetResolverTests (failing)"
```

(Run `xcodegen generate` so the new test file registers.)
