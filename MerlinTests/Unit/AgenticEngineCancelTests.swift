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
