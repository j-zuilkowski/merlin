# Phase 275a — Context-Overrun Retry Bound (failing test)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 274b complete: chip-freshness fix + CI gate landed; two regressions deferred here
and to 276.

**Regression being fixed.** When a provider returns a context-length / body-size `400`
on *every* call, `AgenticEngine` calls the provider ~199 times and never yields a
terminal event. Root cause: `EscalationHandler.escalateOrStop` only increments its
`successfulRefinements` budget on the `.decomposed` outcome. The `.cannotDecompose` →
`.routeToProvider` branch (`EscalationHandler.swift:61`) returns without consuming the
budget, so repeated overruns loop `.routeToProvider` → `continue turnLoop` → overrun →
escalate → `.routeToProvider` … until the outer `maxLoopIterations` cap. Phase 237's
`maxRefinementsPerTurn` bound is effectively bypassed.

This phase rewrites the one stale/failing test in `ContextLengthRecoveryTests` to assert
the **correct post-237 behaviour**: repeated context-overrun is bounded to a small
finite number of provider calls and ends with a `.cleanStop` event. (The pre-237
expectations — `callCount == 3`, an `.error` event — are obsolete; phase 237 replaced
the bounded-retry-counter design with `EscalationHandler` + `.cleanStop`.)

The other tests in the file (`test_isContextLengthExceeded_*`,
`test_engine_compacts_and_retries_on_contextLengthExceeded`) are correct and stay
unchanged.

---

## Edit: MerlinTests/Unit/ContextLengthRecoveryTests.swift

Replace the method `test_engine_retries_twice_then_surfaces_error_for_repeated_body_size_failures`
entirely with the method below. Leave every other test in the file unchanged.

```swift
    func test_engine_bounds_retries_and_cleanStops_on_repeated_body_size_failures() async throws {
        // A provider that fails every call with a body-size 400. The engine must NOT
        // retry unboundedly — it must stop after a small finite number of attempts and
        // yield a terminal .cleanStop event (post-237 behaviour).
        let provider = MockProvider(failAllCallsWith:
            ProviderError.httpError(statusCode: 400, body: "maximum request body size exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        // Bounded: 199 calls is the bug. Any small finite cap proves the fix. The exact
        // count depends on planner refine calls; the contract is "finite and small".
        XCTAssertGreaterThanOrEqual(provider.callCount, 2,
            "engine must attempt at least one recovery retry")
        XCTAssertLessThanOrEqual(provider.callCount, 12,
            "repeated context-overrun must be bounded, not loop ~199 times; got \(provider.callCount)")

        // The turn must terminate with a clean stop.
        let cleanStops = events.compactMap { event -> String? in
            if case .cleanStop(let reason, _) = event { return reason }
            return nil
        }
        XCTAssertFalse(cleanStops.isEmpty,
            "repeated unrecoverable overrun must yield a .cleanStop terminal event")

        // A context-overrun system note must have surfaced.
        let notes = events.compactMap { event -> String? in
            if case .systemNote(let note) = event { return note }
            return nil
        }
        XCTAssertTrue(notes.contains(where: { $0.lowercased().contains("overrun") }),
            "must emit a context-overrun note; notes: \(notes)")
    }
```

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

Expected: **BUILD SUCCEEDED**, but
`test_engine_bounds_retries_and_cleanStops_on_repeated_body_size_failures`
**FAILS at runtime** — the current engine loops ~199 times and yields no `.cleanStop`.
That failure is the red state this phase establishes; 275b makes it pass.

## Commit

```bash
git add tasks/task-275a-context-overrun-bound-tests.md \
    MerlinTests/Unit/ContextLengthRecoveryTests.swift
git commit -m "Phase 275a — ContextOverrunBoundTest (failing)"
```
