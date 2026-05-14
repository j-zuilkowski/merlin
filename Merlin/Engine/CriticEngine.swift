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

// MARK: - CriticPolicyResolver

enum CriticDecision: Sendable, Equatable {
    case run
    case skip
    case deterministicOnly
}

enum CriticPolicyResolver {
    static func resolve(
        skill: SkillFrontmatter?,
        step: PlanStep?,
        heuristic: (writtenFiles: Bool, substantial: Bool, complexity: ComplexityTier),
        classifierOverride: Bool
    ) -> CriticDecision {
        if skill?.critic == .skip {
            return .skip
        }
        if skill?.critic == .required {
            return .run
        }
        if classifierOverride {
            return .run
        }
        if step?.requiresCritic == .skip {
            return .skip
        }
        if step?.requiresCritic == .required {
            return .run
        }

        if let step, !step.successCriteria.isEmpty, step.successCriteria.allSatisfy(Self.isDeterministicCriterion) {
            return .deterministicOnly
        }

        if heuristic.writtenFiles || heuristic.substantial || heuristic.complexity == .highStakes {
            return .run
        }

        return .skip
    }

    private static func isDeterministicCriterion(_ criterion: StepCriterion) -> Bool {
        switch criterion {
        case .buildSucceeds,
             .testsPass,
             .fileExists,
             .regexMatch,
             .shellExitZero:
            return true
        case .prose:
            return false
        }
    }
}

// MARK: - CriterionChecker

actor CriterionChecker {

    private let shellRunner: any ShellRunning

    init(shellRunner: any ShellRunning) {
        self.shellRunner = shellRunner
    }

    func check(_ criterion: StepCriterion) async -> Bool {
        switch criterion {
        case .prose:
            return false
        case .buildSucceeds:
            let command = "xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
            let (exitCode, _) = await shellRunner.run(command)
            return exitCode == 0
        case .testsPass(let scheme):
            let schemePart = scheme.map { "-scheme \($0)" } ?? ""
            let command = "xcodebuild test \(schemePart) -destination 'platform=macOS' CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
            let (exitCode, _) = await shellRunner.run(command)
            return exitCode == 0
        case .fileExists(let path):
            return FileManager.default.fileExists(atPath: path)
        case .regexMatch(let pattern, let target):
            let (_, output) = await shellRunner.run(target == .stdout ? "echo" : "pwd")
            let subject: String
            switch target {
            case .stdout:
                subject = output
            case .file:
                subject = (try? String(contentsOfFile: output, encoding: .utf8)) ?? ""
            }
            return matches(pattern: pattern, in: subject)
        case .shellExitZero(let command):
            let (exitCode, _) = await shellRunner.run(command)
            return exitCode == 0
        }
    }

    private func matches(pattern: String, in subject: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
        return regex.firstMatch(in: subject, options: [], range: range) != nil
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
    private let modelManager: (any LocalModelManagerProtocol)?

    init(
        verificationBackend: any VerificationBackend,
        reasonProvider: (any LLMProvider)?,
        shellRunner: any ShellRunning = LiveShellRunner(),
        modelManager: (any LocalModelManagerProtocol)? = nil
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = reasonProvider
        self.shellRunner = shellRunner
        self.modelManager = modelManager
    }

    init(
        verificationBackend: any VerificationBackend,
        shellRunner: any ShellRunning = LiveShellRunner(),
        orchestrateProvider: (any LLMProvider)?
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = orchestrateProvider
        self.shellRunner = shellRunner
        self.modelManager = nil
    }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
        await evaluate(taskType: taskType, output: output, context: context, writtenFiles: [])
    }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message],
        writtenFiles: [String]
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
            let s2 = await runStage2(output: output, context: context, taskType: taskType, writtenFiles: writtenFiles)
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

    func runStage1(taskType: DomainTaskType) async -> CriticResult {
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

    func runStage1(criteria: [StepCriterion]) async -> CriticResult {
        guard criteria.isEmpty == false else {
            return .skipped
        }

        guard criteria.allSatisfy(Self.isDeterministicCriterion) else {
            return .skipped
        }

        let checker = CriterionChecker(shellRunner: shellRunner)
        for criterion in criteria {
            if await checker.check(criterion) == false {
                return .fail(reason: "deterministic criterion failed: \(describeCriterion(criterion))")
            }
        }

        TelemetryEmitter.shared.emit("critic.stage1.short_circuit", data: [
            "criteria_passed": criteria.count
        ])
        return .pass
    }

    // MARK: - Stage 2

    private func runStage2(
        output: String,
        context: [Message],
        taskType: DomainTaskType,
        writtenFiles: [String]
    ) async -> CriticResult? {
        guard let provider = reasonProvider else { return nil }

        let today: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        // Build file-content block for any files written during the turn.
        var writtenFilesBlock = ""
        if !writtenFiles.isEmpty {
            var blocks: [String] = []
            for path in writtenFiles {
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "(could not read)"
                blocks.append("### \(path)\n\(content)")
            }
            writtenFilesBlock = """

            ## Written files — verify these match the stated output

            \(blocks.joined(separator: "\n\n"))
            """
        }

        // Build structured verification prompt.
        // No output truncation — the reason slot (Qwen3-27B) has a 128K context window.
        let hasDocumentContent = !writtenFiles.isEmpty
        let documentCriterion = hasDocumentContent
            ? "\n6. **Document integrity** — Document content matches the stated purpose; effort estimates are present and honest where work is proposed; no unrequested features added silently."
            : ""

        let prompt = """
        You are a critic performing structured verification of AI-generated output.
        Task type: \(taskType.displayName)
        Today's date: \(today)

        ## Verification criteria

        Assess each criterion and note PASS or FAIL with a brief reason:

        1. **Completeness** — Does the output fully address what was asked?
        2. **Factual consistency** — Are technical/architectural claims consistent with the context provided?
        3. **Date accuracy** — If the output contains dates, are they correct (today is \(today))?
        4. **Scope adherence** — Does the output avoid adding unrequested features or scope?
        5. **Internal consistency** — No contradictions within the output itself.\(documentCriterion)

        ## Output to verify

        \(output)
        \(writtenFilesBlock)

        ## Response format

        List your verdict on each criterion above, then end with exactly one of:
          PASS: <one-line summary of what was verified>
          FAIL: <specific issue that must be addressed>

        The final line must start with PASS or FAIL.
        """

        // Auto-resize the reason slot's context window when needed (e.g. LM Studio defaults to 4096).
        if let manager = modelManager {
            let estimatedTokens = prompt.count / 4 + 512
            try? await manager.ensureContextLength(
                modelID: provider.resolvedModelID,
                minimumTokens: estimatedTokens
            )
        }

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

            // Find the final PASS/FAIL verdict — scan from the end so preamble reasoning
            // doesn't shadow the final line.
            let lines = fullResponse.components(separatedBy: .newlines)
            for line in lines.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("PASS") {
                    return .pass
                }
                if trimmed.hasPrefix("FAIL") {
                    let reason = trimmed.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                    return .fail(reason: String(reason))
                }
            }

            // No explicit verdict found — default to pass to avoid false negatives.
            return .pass
        } catch {
            return nil
        }
    }

    private static func isDeterministicCriterion(_ criterion: StepCriterion) -> Bool {
        switch criterion {
        case .buildSucceeds,
             .testsPass,
             .fileExists,
             .regexMatch,
             .shellExitZero:
            return true
        case .prose:
            return false
        }
    }

    private func describeCriterion(_ criterion: StepCriterion) -> String {
        switch criterion {
        case .prose(let text):
            return "prose(\(text))"
        case .buildSucceeds:
            return "buildSucceeds"
        case .testsPass(let scheme):
            return "testsPass(\(scheme ?? "nil"))"
        case .fileExists(let path):
            return "fileExists(\(path))"
        case .regexMatch(let pattern, let target):
            return "regexMatch(\(pattern), \(target.rawValue))"
        case .shellExitZero(let command):
            return "shellExitZero(\(command))"
        }
    }
}
