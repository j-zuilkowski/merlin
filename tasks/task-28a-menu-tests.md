# Phase 28a — Menu Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 27b complete: model picker in provider settings.

New surface introduced in phase 28b:
  - `AgenticEngine.cancel()` + `private var currentTask`
  - `AgenticEngine.send()` emits `.systemNote("[Interrupted]")` on cancellation
  - `AppState.newSession()` — clears context, posts `Notification.Name.merlinNewSession`
  - `AppState.stopEngine()` — cancels engine, resets activity state
  - `Notification.Name.merlinNewSession`

TDD coverage:
  File 1 — AgenticEngineCancelTests: cancel() + CancellationError → [Interrupted]
  File 2 — AppStateSessionTests: newSession clears context + posts notification

---

## Write to: MerlinTests/Unit/AgenticEngineCancelTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - SlowProvider
// Simulates a provider that streams one chunk then hangs, allowing cancel() to be tested.

private final class SlowProvider: LLMProvider, @unchecked Sendable {
    let id = "slow"
    let baseURL = URL(string: "http://localhost")!

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(CompletionChunk(
                    delta: .init(content: "partial"), finishReason: nil))
                // Hang until cancelled
                try await Task.sleep(nanoseconds: 60_000_000_000)
                continuation.finish()
            }
        }
    }
}

// MARK: - AgenticEngineCancelTests

@MainActor
final class AgenticEngineCancelTests: XCTestCase {

    private func makeEngine() -> AgenticEngine {
        let slow = SlowProvider()
        return AgenticEngine(
            proProvider: slow,
            flashProvider: slow,
            visionProvider: slow,
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-cancel-test.json"),
                presenter: NoOpAuthPresenter()
            )),
            contextManager: ContextManager()
        )
    }

    // cancel() when no task is running must not crash
    func testCancelWhenIdleDoesNotCrash() {
        let engine = makeEngine()
        engine.cancel() // must not throw or crash
    }

    // cancel() during an active send() produces [Interrupted] system note
    func testCancelEmitsInterruptedNote() async {
        let engine = makeEngine()
        var events: [AgentEvent] = []

        // Start the stream in a detached task so we can cancel concurrently
        let streamTask = Task { @MainActor in
            for await event in engine.send(userMessage: "hello") {
                events.append(event)
            }
        }

        // Give the engine time to start and yield the first chunk
        try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        engine.cancel()
        await streamTask.value

        let notes = events.compactMap {
            if case .systemNote(let text) = $0 { return text } else { return nil }
        }
        XCTAssertTrue(notes.contains("[Interrupted]"),
                      "Expected [Interrupted] system note after cancel(); got \(events)")
    }

    // After cancel(), a new send() works normally
    func testNewSendAfterCancelSucceeds() async {
        let engine = makeEngine()

        // Cancel immediately without sending anything
        engine.cancel()

        // Now wire a fast CapturingProvider and verify send() still works
        let fast = CapturingProvider()
        engine.proProvider = fast
        engine.flashProvider = fast

        var receivedText = false
        for await event in engine.send(userMessage: "hi") {
            if case .text = event { receivedText = true }
        }
        XCTAssertTrue(receivedText)
    }
}

// MARK: - NoOpAuthPresenter

private final class NoOpAuthPresenter: AuthPresenter, @unchecked Sendable {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        .deny
    }
}
```

---

## Write to: MerlinTests/Unit/AppStateSessionTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for AppState.newSession() and stopEngine().
// AppState creates real Keychain entries and file-system paths, so tests use
// a narrow surface: only the observable effects (context cleared, notification posted).

@MainActor
final class AppStateSessionTests: XCTestCase {

    // MARK: Notification name

    func testNewSessionNotificationNameIsStable() {
        XCTAssertEqual(
            Notification.Name.merlinNewSession.rawValue,
            "com.merlin.newSession"
        )
    }

    // MARK: newSession clears engine context

    func testNewSessionClearsEngineContext() async throws {
        let appState = AppState()

        // Seed the context with a message
        appState.engine.contextManager.append(
            Message(role: .user, content: .text("hello"), timestamp: Date()))
        XCTAssertFalse(appState.engine.contextManager.messages.isEmpty,
                       "Precondition: context must be non-empty before newSession()")

        appState.newSession()

        XCTAssertTrue(appState.engine.contextManager.messages.isEmpty,
                      "newSession() must clear the engine context")
    }

    // MARK: newSession posts notification

    func testNewSessionPostsNotification() async throws {
        let appState = AppState()

        let expectation = XCTestExpectation(description: "merlinNewSession notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .merlinNewSession,
            object: nil,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        appState.newSession()

        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: stopEngine resets activity state

    func testStopEngineResetsActivityState() {
        let appState = AppState()
        appState.toolActivityState = .streaming

        appState.stopEngine()

        XCTAssertEqual(appState.toolActivityState, .idle)
        XCTAssertFalse(appState.thinkingModeActive)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AgenticEngine.cancel()`,
`AppState.newSession()`, `AppState.stopEngine()`, `Notification.Name.merlinNewSession`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineCancelTests.swift \
        MerlinTests/Unit/AppStateSessionTests.swift
git commit -m "Phase 28a — AgenticEngineCancelTests + AppStateSessionTests (failing)"
```
