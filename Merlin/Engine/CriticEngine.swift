import Foundation

// MARK: - CriticResult

enum CriticResult: Equatable, Sendable {
    case pass
    case fail(reason: String)
    case skipped
}

// MARK: - ShellRunning

/// Protocol for running shell commands - testable without ShellTool dependency.
protocol ShellRunning: Sendable {
    func run(_ command: String) async -> (exitCode: Int, output: String)
}

struct LiveShellRunner: ShellRunning {
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (Int(process.terminationStatus), output))
                } catch {
                    continuation.resume(returning: (1, error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - CriticEngine

/// Two-stage critic:
///   Stage 1 - deterministic domain verification (VerificationBackend -> ShellTool)
///   Stage 2 - reason-slot model evaluation (graceful degradation if unavailable)
actor CriticEngine {

    private let verificationBackend: any VerificationBackend
    private let reasonProvider: (any LLMProvider)?
    private let shellRunner: any ShellRunning

    init(
        verificationBackend: any VerificationBackend,
        reasonProvider: (any LLMProvider)?,
        shellRunner: any ShellRunning = LiveShellRunner()
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = reasonProvider
        self.shellRunner = shellRunner
    }

    init(
        verificationBackend: any VerificationBackend,
        shellRunner: any ShellRunning = LiveShellRunner(),
        orchestrateProvider: (any LLMProvider)?
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = orchestrateProvider
        self.shellRunner = shellRunner
    }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
        TelemetryEmitter.shared.emit("critic.evaluate.start", data: [
            "task_type": taskType.name
        ])
        let evalStart = Date()
        let stage1Result = await runStage1(taskType: taskType)

        let finalResult: CriticResult
        switch stage1Result {
        case .fail(let reason):
            finalResult = .fail(reason: reason)
            TelemetryEmitter.shared.emit("critic.evaluate.fail", data: [
                "reason": reason,
                "stage": "stage1"
            ])
        case .pass, .skipped:
            let s2 = await runStage2(output: output, context: context, taskType: taskType)
            finalResult = s2 ?? (stage1Result == .pass ? .pass : .skipped)
            if case .fail(let reason) = finalResult {
                TelemetryEmitter.shared.emit("critic.evaluate.fail", data: [
                    "reason": reason,
                    "stage": "stage2"
                ])
            }
        }

        let ms = Date().timeIntervalSince(evalStart) * 1000
        let resultStr: String
        switch finalResult {
        case .pass:
            resultStr = "pass"
        case .fail:
            resultStr = "fail"
        case .skipped:
            resultStr = "skipped"
        }
        TelemetryEmitter.shared.emit("critic.evaluate.complete", durationMs: ms, data: [
            "task_type": taskType.name,
            "result": resultStr
        ])
        return finalResult
    }

    // MARK: - Stage 1

    private func runStage1(taskType: DomainTaskType) async -> CriticResult {
        let commands = await verificationBackend.verificationCommands(for: taskType)
        guard let commands, !commands.isEmpty else {
            return .skipped
        }

        for cmd in commands {
            let (exitCode, output) = await shellRunner.run(cmd.command)
            let passed: Bool
            switch cmd.passCondition {
            case .exitCode(let expected):
                passed = exitCode == expected
            case .outputContains(let substring):
                passed = output.contains(substring)
            case .custom(let predicate):
                passed = predicate(output)
            }
            if !passed {
                return .fail(reason: "\(cmd.label) failed\(output.isEmpty ? "" : ": \(output.prefix(200))")")
            }
        }
        return .pass
    }

    // MARK: - Stage 2

    private func runStage2(
        output: String,
        context: [Message],
        taskType: DomainTaskType
    ) async -> CriticResult? {
        guard let provider = reasonProvider else { return nil }

        let prompt = """
        You are a critic reviewing AI-generated output for a \(taskType.displayName) task.
        Review the following output and respond with exactly one of:
          PASS: <brief reason>
          FAIL: <specific issue>

        Output to review:
        \(output.prefix(4000))
        """

        var request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )
        let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
        inferenceDefaults.apply(to: &request)

        do {
            var fullResponse = ""
            let stream = try await provider.complete(request: request)
            for try await chunk in stream {
                fullResponse += chunk.delta?.content ?? ""
            }

            let trimmed = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("PASS") {
                return .pass
            }
            if trimmed.hasPrefix("FAIL") {
                let reason = trimmed.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                return .fail(reason: String(reason))
            }

            return .pass
        } catch {
            return nil
        }
    }
}
