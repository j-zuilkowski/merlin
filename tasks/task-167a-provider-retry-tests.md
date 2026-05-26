# Task 167a — Provider Retry Policy Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 166b complete: WKWebView chat renderer in place.

Transient provider errors (429, 5xx, network drops) currently kill the engine run immediately
after the provider exhausts its internal retries. The fix introduces `ProviderError` — a
structured error type that classifies HTTP errors as retriable or non-retriable — and adds an
engine-level retry loop around `provider.complete(request:)` so the run survives transient
failures with a visible `systemNote` rather than dying.

New surface introduced in task 167b:
  - `ProviderError` — `Error` enum: `.httpError(statusCode:body:providerID:)`, `.networkError(underlying:providerID:)`
  - `ProviderError.isRetriable` — `Bool`; true for 429 and 500–599; retriable URLError codes
  - `ProviderError.retryDelay` — `TimeInterval`; 10s for 429, 5s for 5xx, 3s for network
  - `ProviderError.statusCode` — `Int?`; nil for network errors
  - `MockProvider.stubbedErrors` — `[Error?]`; nil entry = succeed; non-nil = throw that error
  - `AgenticEngine` — wraps `provider.complete` in 3-attempt retry loop; emits `.systemNote` on each retry

TDD coverage:
  File 1 — ProviderRetryPolicyTests: isRetriable classification, retryDelay values, statusCode
  File 2 — EngineProviderRetryTests: engine emits systemNote and resumes; hard-fails on non-retriable; hard-fails after max retries

---

## Edit: TestHelpers/MockProvider.swift

Add error injection support. Insert after `private var responseIndex = 0`:

```swift
    /// Optional error sequence. Each call to `complete` consumes one entry (nil = succeed normally).
    /// After the array is exhausted every subsequent call succeeds normally using `chunks`/`responses`.
    var stubbedErrors: [Error?] = []
    private var errorIndex = 0
```

And at the top of `complete(request:)`, before `wasUsed = true`, insert:

```swift
        if errorIndex < stubbedErrors.count {
            let maybeError = stubbedErrors[errorIndex]
            errorIndex += 1
            if let error = maybeError { throw error }
        }
```

---

## Write to: MerlinTests/Unit/ProviderRetryPolicyTests.swift

```swift
import XCTest
@testable import Merlin

final class ProviderRetryPolicyTests: XCTestCase {

    // MARK: - isRetriable

    func test_httpError_429_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 429, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_500_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 500, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_502_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 502, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_503_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 503, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_504_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 504, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_401_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 401, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_403_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 403, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_400_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 400, body: "", providerID: "p").isRetriable)
    }

    func test_networkError_timeout_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").isRetriable)
    }

    func test_networkError_connectionLost_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.networkConnectionLost), providerID: "p").isRetriable)
    }

    func test_networkError_notConnected_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.notConnectedToInternet), providerID: "p").isRetriable)
    }

    // MARK: - retryDelay

    func test_retryDelay_429_is10s() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 429, body: "", providerID: "p").retryDelay, 10)
    }

    func test_retryDelay_500_is5s() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 500, body: "", providerID: "p").retryDelay, 5)
    }

    func test_retryDelay_networkError_is3s() {
        XCTAssertEqual(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").retryDelay, 3)
    }

    // MARK: - statusCode

    func test_statusCode_httpError() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 503, body: "", providerID: "p").statusCode, 503)
    }

    func test_statusCode_networkError_isNil() {
        XCTAssertNil(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").statusCode)
    }
}
```

---

## Write to: MerlinTests/Unit/EngineProviderRetryTests.swift

```swift
import XCTest
@testable import Merlin

final class EngineProviderRetryTests: XCTestCase {

    // MARK: - helpers

    @MainActor
    private func events(from engine: AgenticEngine) async -> [AgentEvent] {
        var result: [AgentEvent] = []
        for await event in engine.send(userMessage: "ping") {
            result.append(event)
        }
        return result
    }

    // MARK: - tests

    /// One transient 503 → engine emits a "retrying" systemNote then succeeds.
    func test_engineEmitsSystemNote_andResumes_onSingleTransientError() async throws {
        let provider = MockProvider(chunks: [.assistant("hello")])
        provider.stubbedErrors = [
            ProviderError.httpError(statusCode: 503, body: "unavailable", providerID: "mock")
        ]
        let engine = await makeEngine(provider: provider)

        let evts = await events(from: engine)

        let notes = evts.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertTrue(notes.contains(where: { $0.contains("retrying") }),
                      "Expected a retry systemNote; got: \(notes)")

        let texts = evts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        XCTAssertTrue(texts.joined().contains("hello"),
                      "Expected success text after retry; got: \(texts)")
    }

    /// Non-retriable 401 → engine hard-fails immediately, no retry note.
    func test_engineHardFails_onNonRetriableError() async throws {
        let provider = MockProvider(chunks: [])
        provider.stubbedErrors = [
            ProviderError.httpError(statusCode: 401, body: "unauthorized", providerID: "mock")
        ]
        let engine = await makeEngine(provider: provider)

        let evts = await events(from: engine)

        let errors = evts.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
        XCTAssertFalse(errors.isEmpty, "Expected error event for 401")

        let retryNotes = evts.compactMap { if case .systemNote(let s) = $0, s.contains("retrying") { return s } else { return nil } }
        XCTAssertTrue(retryNotes.isEmpty, "Should not retry a 401; got notes: \(retryNotes)")
    }

    /// Max retries exhausted → engine hard-fails after emitting exactly 2 retry notes (3 attempts).
    func test_engineHardFails_afterMaxRetries() async throws {
        let err = ProviderError.httpError(statusCode: 503, body: "down", providerID: "mock")
        let provider = MockProvider(chunks: [])
        // 3 failures — exceeds the 3-attempt (2-retry) engine limit
        provider.stubbedErrors = [err, err, err]
        let engine = await makeEngine(provider: provider)

        let evts = await events(from: engine)

        let errors = evts.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
        XCTAssertFalse(errors.isEmpty, "Expected error event after max retries")

        let retryNotes = evts.compactMap { if case .systemNote(let s) = $0, s.contains("retrying") { return s } else { return nil } }
        XCTAssertEqual(retryNotes.count, 2, "Expected exactly 2 retry notes (3-attempt loop); got: \(retryNotes)")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `ProviderError` not found, `MockProvider.stubbedErrors` not found.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ProviderRetryPolicyTests.swift \
        MerlinTests/Unit/EngineProviderRetryTests.swift \
        tasks/task-167a-provider-retry-tests.md
git commit -m "Task 167a — ProviderRetryPolicyTests, EngineProviderRetryTests (failing)"
```
