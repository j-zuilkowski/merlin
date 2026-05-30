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
        case continuationLimitExceeded
    }

    /// Creates a `LiveSession` rooted at `fixturePath`, sends `prompt` through the
    /// engine, and collects the event stream until the agentic loop ends or `timeout`
    /// elapses. Uses the configured providers/slots (LM Studio + DeepSeek) - no mocks.
    @MainActor
    static func runScenario(
        fixturePath: String,
        prompt: String,
        timeout: TimeInterval = 1800,
        activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs
    ) async throws -> EvalRun {
        // Standard pipeline: ensure LM Studio has the execute-slot model resident
        // before the scenario runs. Idempotent — a no-op when it is already loaded;
        // this is also what reloads it after S5's training unloads it.
        EvalLMStudio.ensureExecuteSlotModelLoaded()

        let session = LiveSession(
            projectRef: ProjectRef(path: fixturePath,
                                   displayName: "eval",
                                   lastOpenedAt: Date()),
            activeDomainIDs: activeDomainIDs)
        guard let engine = session.appState.engine else {
            await session.close()
            throw HarnessError.engineUnavailable
        }
        if getenv("XCALIBRE_TOKEN") != nil || !AppSettings.shared.xcalibreToken.isEmpty {
            await session.appState.xcalibreClient.probe()
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

        let continuationDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-eval-continuation-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: continuationDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: continuationDir) }
        let continuationURL = continuationDir.appendingPathComponent("inject.txt")
        engine.continuationInjectURL = continuationURL

        let deadline = Date().addingTimeInterval(timeout)
        var nextPrompt: String? = prompt
        var continuationTurns = 0
        let maxContinuationTurns = 20

        while let currentPrompt = nextPrompt {
            nextPrompt = nil
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                let collected = EvalRun(
                    assistantText: text,
                    toolCalls: order.compactMap { tools[$0] },
                    systemNotes: notes,
                    errors: errors,
                    allEvents: all)
                writeTimeoutDiagnostic(prompt: prompt, timeout: timeout, run: collected)
                await session.close()
                throw HarnessError.timedOut
            }

            // Hard wall-clock bound for this stream. Closing the session cancels a
            // stalled engine.send() even when no events arrive, while the outer
            // deadline remains shared across continuation turns.
            let watchdog = Task { @MainActor in
                try? await Task.sleep(for: .seconds(remaining))
                guard Task.isCancelled == false else { return }
                await session.close()
            }

            eventLoop: for await event in engine.send(userMessage: currentPrompt) {
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
                        if activeDomainIDs.contains(ElectronicsDomain.defaultID),
                           existing.name == "workflow.requirements_to_pcb"
                            || existing.name == "workflow.schematic_to_pcb" {
                            if let validationFailure = validateElectronicsWorkflowResult(result.content) {
                                tools[result.toolCallId] = ToolCallRecord(
                                    name: existing.name,
                                    arguments: existing.arguments,
                                    result: "ELECTRONICS_WORKFLOW_VALIDATION_FAILED: \(validationFailure)",
                                    isError: true)
                                await session.close()
                                break eventLoop
                            }
                            await session.close()
                            break eventLoop
                        }
                    }
                default: break
                }
            }
            watchdog.cancel()

            if FileManager.default.fileExists(atPath: continuationURL.path),
               let continuation = try? String(contentsOf: continuationURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               continuation.hasPrefix("[CONTINUATION]") {
                try? FileManager.default.removeItem(at: continuationURL)
                continuationTurns += 1
                guard continuationTurns <= maxContinuationTurns else {
                    await session.close()
                    throw HarnessError.continuationLimitExceeded
                }
                nextPrompt = continuation
            }
        }
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

    /// S6 is a workflow-contract scenario, not a free-form chat benchmark. Once the
    /// first-party electronics workflow returns, the harness validates the returned
    /// report directly and stops the loop. This keeps provider differences from
    /// turning a complete workflow into extra, model-improvised shell/UI probing.
    private static func validateElectronicsWorkflowResult(_ content: String) -> String? {
        guard let report = try? WorkspaceJSON.decoder.decode(
            ElectronicsFinalReport.self,
            from: Data(content.utf8)
        ) else {
            return "workflow did not return an ElectronicsFinalReport payload"
        }

        guard report.status == .complete else {
            return "workflow status is \(report.status.rawValue)"
        }
        if let failed = report.gates.first(where: { $0.status != .pass }) {
            return "\(failed.gate.rawValue) gate is \(failed.status.rawValue): \(failed.details)"
        }
        for artifact in report.artifacts where !FileManager.default.fileExists(atPath: artifact.path) {
            return "missing artifact \(artifact.kind.rawValue) at \(artifact.path)"
        }
        guard let simulation = report.gates.first(where: { $0.gate == .simulation }),
              simulation.details.lowercased().contains("ngspice") else {
            return "simulation gate does not cite ngspice evidence"
        }
        guard let spice = report.artifacts.first(where: { $0.kind == .spiceMeasurements }),
              let measurements = try? String(contentsOfFile: spice.path, encoding: .utf8),
              measurements.range(of: #"frequency\s*="#, options: .regularExpression) != nil else {
            return "missing ngspice frequency measurement artifact"
        }
        return nil
    }
}
