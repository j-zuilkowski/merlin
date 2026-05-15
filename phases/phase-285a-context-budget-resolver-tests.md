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

New surface introduced in phase 285b:
  - `ContextBudgetResolver` actor in `Merlin/Engine/ContextBudgetResolver.swift`:
    ```swift
    actor ContextBudgetResolver {
        /// `source` discovers the raw context-window size (tokens) for a provider, or
        /// nil when it cannot. Injectable so tests are deterministic; the production
        /// initialiser uses a source that queries local runners and a model map.
        init(reservedOutputTokens: Int = 4_096,
             conservativeContextTokens: Int = 32_000,
             ttl: TimeInterval = 300,
             source: @escaping @Sendable (any LLMProvider) async -> Int?)

        /// Usable input-token budget for `provider`: discovered context minus reserved
        /// output, floored at a safe minimum. Cached per `provider.id` for `ttl`.
        func usableInputTokens(for provider: any LLMProvider) async -> Int
    }
    ```

TDD coverage:
  File 1 — `MerlinTests/Unit/ContextBudgetResolverTests.swift`: a source that reports a
    context size yields `size − reservedOutput`; a source that returns nil yields the
    conservative fallback minus reserved output; the result is never below a floor; the
    source is consulted once per provider within the TTL (caching).

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

    func testDiscoveredContextYieldsContextMinusReservedOutput() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in 8_192 })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 8_192 - 4_096)
    }

    func testNilDiscoveryFallsBackToConservative() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in nil })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 32_000 - 4_096)
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

Expected: **BUILD FAILED** — errors naming the missing `ContextBudgetResolver`.

## Commit

```bash
git add phases/phase-285a-context-budget-resolver-tests.md \
    MerlinTests/Unit/ContextBudgetResolverTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 285a — ContextBudgetResolverTests (failing)"
```

(Run `xcodegen generate` so the new test file registers.)
