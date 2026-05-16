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
        let session = LiveSession(
            projectRef: ProjectRef(path: fixturePath,
                                   displayName: "eval",
                                   lastOpenedAt: Date()))
        guard let engine = session.appState.engine else {
            await session.close()
            throw HarnessError.engineUnavailable
        }

        var text = ""
        var tools: [String: ToolCallRecord] = [:]
        var order: [String] = []
        var notes: [String] = []
        var errors: [String] = []
        var all: [AgentEvent] = []

        let deadline = Date().addingTimeInterval(timeout)
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
            if Date() > deadline {
                await session.close()
                throw HarnessError.timedOut
            }
        }
        await session.close()

        return EvalRun(
            assistantText: text,
            toolCalls: order.compactMap { tools[$0] },
            systemNotes: notes,
            errors: errors,
            allEvents: all)
    }
}
