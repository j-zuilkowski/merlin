# Task 178a — ProviderTelemetryTests: URLError retry event missing (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 177b complete: provider(for:) NullProvider and vision fallback fix.

## Problem

`ProviderTelemetryTests.testOpenAICompatibleEmitsRetryEvent` fails because:

The test's `MockTelemetryURLProtocol` throws `URLError(.badServerResponse)` on the
first attempt (when `failFirstAttempt = true`). The retry logic in
`OpenAICompatibleProvider.complete` has TWO retry paths:

**Path 1** (top of loop, `attempt > 1`): Creates a new `URLSession(configuration: .ephemeral)`,
emits `request.retry`, sleeps, then proceeds to `bytes(for:)`.

**Path 2** (catch, `ProviderError.isRetriable`): Emits `request.retry`, creates new session,
sleeps, continues loop.

**Path 3** (generic catch): Catches `URLError(.badServerResponse)`. Since `URLError` is NOT
a `ProviderError`, it falls into the generic `catch { ... }` which calls
`continuation.finish(throwing: error)` WITHOUT retrying.

So a `URLError` thrown by the mock is caught by the generic handler and terminates
immediately — no retry event is emitted.

Additionally, Path 1 creates a NEW `URLSession` for retries, which loses the mock
`URLProtocol` class (only registered on the original session), so even if retry happened
the mock wouldn't be used.

Failing test: `testOpenAICompatibleEmitsRetryEvent`

Root cause in `Merlin/Providers/OpenAICompatibleProvider.swift` ~line 127-145:
```swift
} catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
    // ... emits request.retry ...
    currentSession = URLSession(configuration: .ephemeral)   // loses mock protocol
    continue
} catch {
    // URLError ends up here — no retry, no event
    continuation.finish(throwing: error)
    return
}
```

## Existing test file

`MerlinTests/Unit/ProviderTelemetryTests.swift` — already committed.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProviderTelemetry.*failed|BUILD' | head -10
```

Expected: `testOpenAICompatibleEmitsRetryEvent` fails.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-178a-provider-telemetry-retry-tests.md
git commit -m "Task 178a — ProviderTelemetry URLError retry failure documented"
```
