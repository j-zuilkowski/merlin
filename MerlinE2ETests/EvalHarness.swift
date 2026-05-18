import Foundation
@testable import Merlin

/// One tool invocation captured during a scenario run.
struct ToolCallRecord: Sendable {
    let name: String
    let arguments: String
    let result: String?
    let isError: Bool
}

/// Captured result of one eval scenario run.
struct EvalRun: Sendable {
    let assistantText: String        // concatenated .text events
    let toolCalls: [ToolCallRecord]
    let systemNotes: [String]        // .systemNote events
    let errors: [String]             // .error events
    let allEvents: [AgentEvent]
}

/// Drives a real LiveSession over a fixture project for the proving suite.
enum EvalHarness {

    enum HarnessError: Error {
        case engineUnavailable
        case timedOut
    }

    /// Creates a `LiveSession` rooted at `fixturePath`, sends `prompt` through the
    /// engine, and collects the event stream until the agentic loop ends or `timeout`
    /// elapses. Uses the configured providers/slots (LM Studio + DeepSeek) - no mocks.
    @MainActor
    static func runScenario(
        fixturePath: String,
        prompt: String,
        timeout: TimeInterval = 1800
    ) async throws -> EvalRun {
        // Standard pipeline: ensure LM Studio has the execute-slot model resident
        // before the scenario runs. Idempotent — a no-op when it is already loaded;
        // this is also what reloads it after S5's training unloads it.
        EvalLMStudio.ensureExecuteSlotModelLoaded()

        let session = LiveSession(
            projectRef: ProjectRef(path: fixturePath,
                                   displayName: "eval",
                                   lastOpenedAt: Date()))
        guard let engine = session.appState.engine else {
            await session.close()
            throw HarnessError.engineUnavailable
        }

        // Wait for MCP servers to finish launching and registering their tools.
        // LiveSession starts them in a background task; sending the prompt before
        // it completes races registration and the model's first turn is offered
        // no MCP tools (e.g. S6 sees no kicad_* tools and improvises).
        await session.awaitMCPReady()

        var text = ""
        var tools: [String: ToolCallRecord] = [:]
        var order: [String] = []
        var notes: [String] = []
        var errors: [String] = []
        var all: [AgentEvent] = []

        let deadline = Date().addingTimeInterval(timeout)

        // Hard wall-clock bound. A watchdog closes the session after `timeout` even
        // when the event stream stalls entirely and produces nothing — closing
        // cancels the engine, whose stream cancellation handler ends the `for await`
        // below. An in-loop deadline check (the previous design) cannot fire on a
        // stalled stream, so a hung scenario could block the whole suite forever.
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard Task.isCancelled == false else { return }
            await session.close()
        }

        for await event in engine.send(userMessage: prompt) {
            all.append(event)
            switch event {
            case .text(let t): text += t
            case .systemNote(let n): notes.append(n)
            case .error(let e): errors.append(String(describing: e))
            case .toolCallStarted(let call):
                order.append(call.id)
                tools[call.id] = ToolCallRecord(
                    name: call.function.name, arguments: call.function.arguments,
                    result: nil, isError: false)
            case .toolCallResult(let result):
                if let existing = tools[result.toolCallId] {
                    tools[result.toolCallId] = ToolCallRecord(
                        name: existing.name, arguments: existing.arguments,
                        result: result.content, isError: result.isError)
                }
            default: break
            }
        }
        watchdog.cancel()
        await session.close()

        let collected = EvalRun(
            assistantText: text,
            toolCalls: order.compactMap { tools[$0] },
            systemNotes: notes,
            errors: errors,
            allEvents: all)

        if Date() > deadline {
            // A timeout otherwise discards everything the scenario produced.
            // Dump the partial run so a hung scenario (e.g. S1) is diagnosable.
            writeTimeoutDiagnostic(prompt: prompt, timeout: timeout, run: collected)
            throw HarnessError.timedOut
        }

        return collected
    }

    /// Writes the partial run of a timed-out scenario to a temp file for triage.
    private static func writeTimeoutDiagnostic(
        prompt: String, timeout: TimeInterval, run: EvalRun
    ) {
        let toolLines = run.toolCalls.map {
            "  \($0.name)(\($0.arguments.prefix(160)))"
                + ($0.isError ? " [ERROR]" : "")
        }.joined(separator: "\n")
        let dump = """
        TIMED OUT after \(Int(timeout))s
        prompt: \(prompt.prefix(120))
        tool calls: \(run.toolCalls.count)
        errors: \(run.errors.count)
        --- tools ---
        \(toolLines)
        --- assistantText ---
        \(run.assistantText)
        """
        let path = NSTemporaryDirectory()
            + "merlin-scenario-timeout-\(Int(Date().timeIntervalSince1970)).md"
        try? dump.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
