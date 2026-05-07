# Phase 167b — Provider Retry Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 167a complete: ProviderRetryPolicyTests and EngineProviderRetryTests failing.

---

## New file: Merlin/Providers/ProviderError.swift

```swift
import Foundation

/// Structured error from an LLM provider HTTP request.
///
/// Carries the HTTP status code and response body so callers can classify
/// the failure as retriable (transient) or non-retriable (permanent) and
/// apply appropriate back-off delays.
enum ProviderError: Error, Sendable {
    /// The server responded with a non-2xx HTTP status.
    case httpError(statusCode: Int, body: String, providerID: String)
    /// A transport-level failure occurred before or during the response.
    case networkError(underlying: URLError, providerID: String)

    // MARK: - Classification

    /// True when retrying the request has a reasonable chance of succeeding.
    ///
    /// Retriable:
    ///  - `429 Too Many Requests` — rate-limited; back off and retry.
    ///  - `500…599` — transient server fault.
    ///  - Network timeouts, connection resets, and similar transport errors.
    ///
    /// Non-retriable:
    ///  - `400 Bad Request` — malformed payload; retrying is pointless.
    ///  - `401 / 403` — credential problem; a fresh request won't help.
    ///  - Any other 4xx not listed above.
    var isRetriable: Bool {
        switch self {
        case .httpError(let code, _, _):
            return code == 429 || (500...599).contains(code)
        case .networkError(let err, _):
            return [
                URLError.timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost,
                .badServerResponse,   // connection reset mid-stream
            ].contains(err.code)
        }
    }

    // MARK: - Back-off

    /// Recommended delay before the next retry attempt.
    var retryDelay: TimeInterval {
        switch self {
        case .httpError(429, _, _): return 10   // rate-limited — give the server time to reset
        case .httpError:            return 5    // 5xx — brief pause before retry
        case .networkError:         return 3    // transport error — short pause
        }
    }

    // MARK: - Accessors

    /// The HTTP status code, or `nil` for network errors.
    var statusCode: Int? {
        guard case .httpError(let code, _, _) = self else { return nil }
        return code
    }

    /// Human-readable description suitable for log output.
    var logDescription: String {
        switch self {
        case .httpError(let code, let body, let pid):
            return "[\(pid)] HTTP \(code): \(body.prefix(200))"
        case .networkError(let err, let pid):
            return "[\(pid)] network error \(err.code.rawValue): \(err.localizedDescription)"
        }
    }
}
```

---

## Edit: TestHelpers/MockProvider.swift

Add `stubbedErrors` support so tests can inject a sequence of errors.

After `private var responseIndex = 0`, add:

```swift
    /// Optional error sequence consumed in order by `complete`. A `nil` entry means
    /// "succeed normally". Entries beyond the array length always succeed normally.
    var stubbedErrors: [Error?] = []
    private var errorIndex = 0
```

At the top of `func complete(request: CompletionRequest)`, before `wasUsed = true`, add:

```swift
        if errorIndex < stubbedErrors.count {
            let maybeError = stubbedErrors[errorIndex]
            errorIndex += 1
            if let error = maybeError { throw error }
        }
```

Full updated file:

```swift
import Foundation
@testable import Merlin

final class MockProvider: LLMProvider, @unchecked Sendable {
    var id_: String = "mock"
    var id: String { id_ }
    var baseURL: URL { URL(string: "http://localhost")! }
    var wasUsed = false
    var stubbedResponse: String?
    var stubbedChunks: [String] = []
    private let chunks: [CompletionChunk]
    private var responses: [MockLLMResponse]
    private var responseIndex = 0

    /// Optional error sequence consumed in order by `complete`. A `nil` entry means
    /// "succeed normally". Entries beyond the array length always succeed normally.
    var stubbedErrors: [Error?] = []
    private var errorIndex = 0

    init() { self.chunks = []; self.responses = [] }
    init(chunks: [CompletionChunk]) { self.chunks = chunks; self.responses = [] }
    init(responses: [MockLLMResponse]) { self.chunks = []; self.responses = responses }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        if errorIndex < stubbedErrors.count {
            let maybeError = stubbedErrors[errorIndex]
            errorIndex += 1
            if let error = maybeError { throw error }
        }
        wasUsed = true
        let toSend: [CompletionChunk]
        if let stubbedResponse {
            toSend = [
                CompletionChunk(delta: .init(content: stubbedResponse), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        } else if stubbedChunks.isEmpty == false {
            toSend = stubbedChunks.map { CompletionChunk(delta: .init(content: $0), finishReason: nil) } + [
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        } else if !responses.isEmpty {
            let resp = responses[min(responseIndex, responses.count - 1)]
            responseIndex += 1
            toSend = resp.chunks
        } else {
            toSend = chunks
        }
        return AsyncThrowingStream { continuation in
            for chunk in toSend { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

enum MockLLMResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)

    var chunks: [CompletionChunk] {
        switch self {
        case .text(let s):
            return [
                CompletionChunk(delta: .init(content: s), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        case .toolCall(let id, let name, let args):
            return [
                CompletionChunk(delta: .init(toolCalls: [
                    .init(index: 0, id: id, function: .init(name: name, arguments: args))
                ]), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "tool_calls"),
            ]
        }
    }
}
```

---

## Edit: Merlin/Providers/OpenAICompatibleProvider.swift

Replace the `throw URLError(.badServerResponse, ...)` with `throw ProviderError.httpError(...)`,
and change the retry catch clause to only continue on retriable `ProviderError`.

Replace in the `complete` function:

```swift
                    do {
                        let (bytes, response) = try await currentSession.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode) else {
                            var errorLines: [String] = []
                            for try await line in bytes.lines { errorLines.append(line) }
                            let body = errorLines.joined(separator: "\n").prefix(500)
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            TelemetryEmitter.shared.emit("request.error", data: [
                                "provider": providerID,
                                "error_code": statusCode,
                                "error_detail": String(body)
                            ])
                            throw URLError(.badServerResponse,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
                        }
```

with:

```swift
                    do {
                        let (bytes, response) = try await currentSession.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode) else {
                            var errorLines: [String] = []
                            for try await line in bytes.lines { errorLines.append(line) }
                            let body = errorLines.joined(separator: "\n").prefix(500)
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            TelemetryEmitter.shared.emit("request.error", data: [
                                "provider": providerID,
                                "error_code": statusCode,
                                "error_detail": String(body)
                            ])
                            throw ProviderError.httpError(
                                statusCode: statusCode,
                                body: String(body),
                                providerID: providerID
                            )
                        }
```

And replace the catch clause:

```swift
                    } catch let urlError as URLError
                        where urlError.code == .badServerResponse && attempt < maxAttempts {
                        continue
```

with:

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
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

Add an engine-level retry wrapper around the single `provider.complete(request:)` call at
line 752. The engine makes 3 attempts total (2 retries). On each retry it emits a
`.systemNote` so the user sees activity rather than silence.

Replace:

```swift
                let stream = try await provider.complete(request: request)
```

with:

```swift
                // Engine-level retry for transient provider errors (429, 5xx, network drops).
                // 3 attempts total — provider already has its own internal retry loop for
                // governor-style throttling; this outer loop handles mid-run outages.
                let stream: AsyncThrowingStream<CompletionChunk, Error>
                do {
                    stream = try await Self.completeWithRetry(
                        provider: provider,
                        request: request,
                        maxAttempts: 3,
                        onRetry: { attempt, maxAttempts in
                            continuation.yield(.systemNote(
                                "Provider unavailable — retrying (\(attempt)/\(maxAttempts - 1))…"
                            ))
                        }
                    )
                }
```

Add the static helper method to `AgenticEngine` (place near the bottom of the class, before
the closing brace):

```swift
    /// Calls `provider.complete` up to `maxAttempts` times, retrying on retriable
    /// `ProviderError`s. On each retry `onRetry(attempt, maxAttempts)` is called so
    /// the caller can surface status to the UI. Non-retriable errors and network errors
    /// that are not classified as retriable are re-thrown immediately.
    private static func completeWithRetry(
        provider: any LLMProvider,
        request: CompletionRequest,
        maxAttempts: Int,
        onRetry: @Sendable (Int, Int) -> Void
    ) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        var attempt = 0
        var lastError: Error = URLError(.unknown)
        while attempt < maxAttempts {
            attempt += 1
            do {
                return try await provider.complete(request: request)
            } catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
                lastError = pe
                onRetry(attempt, maxAttempts)
                try await Task.sleep(for: .seconds(pe.retryDelay))
            } catch let pe as ProviderError {
                // Non-retriable ProviderError or retriable but exhausted — throw immediately.
                throw pe
            }
            // URLError or other non-ProviderError falls through to throw below.
        }
        throw lastError
    }
```

---

## Edit: Merlin/Views/ChatView.swift

Update `appendError` to handle `ProviderError` with actionable messages instead of falling
through to the generic NSURLError -1011 path.

In `appendError(_:)`, insert before the `let nsError = error as NSError` line:

```swift
        // ProviderError carries structured HTTP info — map to actionable messages.
        if let pe = error as? ProviderError {
            switch pe {
            case .httpError(let code, _, let pid):
                switch code {
                case 401, 403:
                    items.append(ChatEntry(role: .error,
                        text: "API key rejected by \(pid) (HTTP \(code)). Check your key in Settings → Providers."))
                case 429:
                    items.append(ChatEntry(role: .error,
                        text: "Rate limited by \(pid). The request was retried but the limit persisted. Try again in a moment."))
                default:
                    items.append(ChatEntry(role: .error,
                        text: "\(pid) returned HTTP \(code) after retries. The provider may be temporarily unavailable."))
                }
            case .networkError(_, let pid):
                items.append(ChatEntry(role: .error,
                    text: "Network error connecting to \(pid). Check your connection and try again."))
            }
            bumpRevision()
            return
        }
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all 167a tests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/ProviderError.swift \
        Merlin/Providers/OpenAICompatibleProvider.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/ChatView.swift \
        TestHelpers/MockProvider.swift \
        phases/phase-167b-provider-retry.md
git commit -m "Phase 167b — Provider retry policy (ProviderError + engine-level retry)"
```

---

## Fixes

### Error message copy for 400 / non-5xx codes (2026-05-07)

**Symptom:** HTTP 400 displayed as "returned HTTP 400 after retries. The provider may be
temporarily unavailable." — misleading because 400 is non-retriable and was not retried.

**Fix in `ChatView.appendError`:** Split the `default` case into:
- `400` — actionable message suggesting context compaction (most common cause).
- `401/403` — credential message (unchanged).
- `429` — rate-limit message (unchanged).
- `500...599` — transient server message (was the original `default`).
- `default` — generic fallback for any other code.
