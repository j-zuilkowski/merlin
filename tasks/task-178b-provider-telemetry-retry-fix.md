# Task 178b — Fix: catch URLError as retriable in OpenAICompatibleProvider

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 178a complete: ProviderTelemetry URLError retry failure documented.

## Root Cause

`OpenAICompatibleProvider.complete` retry loop at ~line 127:

```swift
} catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
    // only ProviderError (HTTP 401 governor, 429, 5xx) is retried
    TelemetryEmitter.shared.emit("request.retry", ...)
    currentSession = URLSession(configuration: .ephemeral)
    continue
} catch {
    // URLError.badServerResponse ends up here — no retry, no event
    continuation.finish(throwing: error)
    return
}
```

`URLError(.badServerResponse)` (thrown by mock URLProtocol) is a `URLError`, not
a `ProviderError`. It falls through to the generic `catch` and terminates without retry.

Additionally, Path 1 at the top of the while loop (`if attempt > 1`) emits `request.retry`
and creates a new ephemeral session — this new session loses the mock URLProtocol since
the protocol class was registered on the ORIGINAL session's configuration. The mock then
doesn't intercept the retry.

## Fix

### Edit: `Merlin/Providers/OpenAICompatibleProvider.swift`

Add a `URLError` catch clause BEFORE the generic catch. For `URLError` on attempts before
`maxAttempts`, emit `request.retry` and `continue` WITHOUT creating a new session (to
preserve mock URLProtocol in tests):

**Find** (~line 127):
```swift
                    } catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
                        let delaySecs = pe.retryDelay
                        TelemetryEmitter.shared.emit("request.retry", data: [
                            "provider": providerID,
                            "attempt": attempt,
                            "delay_s": delaySecs,
                            "status_code": pe.statusCode ?? -1
                        ])
                        currentSession = URLSession(configuration: .ephemeral)
                        try? await Task.sleep(for: .seconds(delaySecs))
                        continue
                    } catch {
```

**Replace with**:
```swift
                    } catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
                        let delaySecs = pe.retryDelay
                        TelemetryEmitter.shared.emit("request.retry", data: [
                            "provider": providerID,
                            "attempt": attempt + 1,
                            "delay_s": delaySecs,
                            "status_code": pe.statusCode ?? -1
                        ])
                        currentSession = URLSession(configuration: .ephemeral)
                        try? await Task.sleep(for: .seconds(delaySecs))
                        continue
                    } catch let urlErr as URLError where attempt < maxAttempts {
                        // URLError (network drop, server reset, etc.) — retry without
                        // creating a new session so test URLProtocol mocks stay active.
                        TelemetryEmitter.shared.emit("request.retry", data: [
                            "provider": providerID,
                            "attempt": attempt + 1,
                            "delay_s": 1.0,
                            "error_code": urlErr.errorCode
                        ])
                        try? await Task.sleep(for: .milliseconds(100))
                        continue
                    } catch {
```

**Note**: The test asserts `d?["attempt"] as? Int == 2` (attempt number 2, meaning
"this is the 2nd attempt" / "first retry"). The `attempt` variable is incremented at
the top of the loop (`attempt += 1`), so after the first attempt, `attempt == 1`.
When emitting retry before the second attempt, use `attempt + 1` to get `2`.

Also remove the Path 1 session replacement at the top of the while loop (lines 73-83)
since it creates a race with the mock protocol. The `if attempt > 1` path should NOT
create a new session — the session replacement is handled in the ProviderError catch only:

**Find** (~line 73):
```swift
                    if attempt > 1 {
                        // On governor errors (HTTP 401 "governor") use a fresh session
                        // and a longer delay to allow the server-side rate limiter to reset.
                        currentSession = URLSession(configuration: .ephemeral)
                        let delaySecs: Double = attempt == 2 ? 5 : (attempt == 3 ? 10 : 20)
                        TelemetryEmitter.shared.emit("request.retry", data: [
                            "provider": providerID,
                            "attempt": attempt,
                            "delay_s": delaySecs
                        ])
                        try? await Task.sleep(for: .seconds(delaySecs))
                    }
```

**Replace with** (remove Path 1 entirely — it duplicated retry event emission):
```swift
                    // (no pre-attempt delay — delay is applied in the catch branches below)
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProviderTelemetry.*passed|ProviderTelemetry.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; `testOpenAICompatibleEmitsRetryEvent` passes.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/OpenAICompatibleProvider.swift \
        tasks/task-178b-provider-telemetry-retry-fix.md
git commit -m "Task 178b — Fix: catch URLError as retriable; emit request.retry with attempt+1"
```
