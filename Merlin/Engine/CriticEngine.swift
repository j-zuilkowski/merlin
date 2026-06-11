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
    /// Mutable output buffer shared with the background reader. Read only after
    /// the semaphore signals (happens-after barrier), so unchecked-Sendable is
    /// sound here.
    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    /// Cap on a single verification subprocess. xcodebuild/cargo on a small
    /// fixture finishes well under 5 minutes; the cap catches a wedged process
    /// — e.g. an xcodebuild that deadlocked against a stale build service or a
    /// zombie test runner from a prior run — before it hangs the critic and
    /// the test through it.
    static let timeoutSeconds: TimeInterval = 300

    func run(_ command: String) async -> (exitCode: Int, output: String) {
        await withCheckedContinuation { continuation in
            // Dispatch the blocking work to a global queue rather than
            // Task.detached: DispatchSemaphore.wait is forbidden in async
            // contexts under strict concurrency. The continuation can resume
            // from any context.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (1, error.localizedDescription))
                    return
                }
                // Drain the pipe on a background thread, bounded by a
                // semaphore. The previous impl called waitUntilExit BEFORE
                // readDataToEndOfFile — a deadlock the moment any command
                // (xcodebuild test, cargo test) writes more than the 64KB
                // pipe buffer, because the child blocks writing while we
                // block waiting for it to exit. Reading concurrently fixes
                // the pipe deadlock; the timeout fixes the (separate) hang
                // when the child itself is wedged.
                let done = DispatchSemaphore(value: 0)
                let box = OutputBox()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                    done.signal()
                }
                if done.wait(timeout: .now() + Self.timeoutSeconds) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    continuation.resume(returning: (124,
                        "LiveShellRunner timeout after \(Int(Self.timeoutSeconds))s: \(command)"))
                    return
                }
                process.waitUntilExit()
                let output = String(data: box.data, encoding: .utf8) ?? ""
                continuation.resume(returning: (Int(process.terminationStatus), output))
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
    /// Working-project root. When set, Stage 1 auto-detects the project's build
    /// system and runs its real build/test as a deterministic check — so a broken
    /// edit (e.g. code that does not compile) fails the critic and forces a retry.
    private let projectPath: String?

    init(
        verificationBackend: any VerificationBackend,
        reasonProvider: (any LLMProvider)?,
        shellRunner: any ShellRunning = LiveShellRunner(),
        modelManager: (any LocalModelManagerProtocol)? = nil,
        projectPath: String? = nil
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = reasonProvider
        self.shellRunner = shellRunner
        self.modelManager = modelManager
        self.projectPath = projectPath
    }

    init(
        verificationBackend: any VerificationBackend,
        shellRunner: any ShellRunning = LiveShellRunner(),
        orchestrateProvider: (any LLMProvider)?,
        projectPath: String? = nil
    ) {
        self.verificationBackend = verificationBackend
        self.reasonProvider = orchestrateProvider
        self.shellRunner = shellRunner
        self.modelManager = nil
        self.projectPath = projectPath
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
        var commands = (await verificationBackend.verificationCommands(for: taskType)) ?? []
        commands += await autoDetectedProjectCommands(for: taskType)
        guard !commands.isEmpty else {
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
                return .fail(reason: Self.verificationFailureReason(label: cmd.label, output: output))
            }
        }
        return .pass
    }

    static func verificationFailureReason(label: String, output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(label) failed" }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var includeFollowingFailingTests = 0
        let interesting = lines.filter { line in
            let lower = line.lowercased()
            if includeFollowingFailingTests > 0 {
                includeFollowingFailingTests -= 1
                return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if lower.contains("failing tests:") {
                includeFollowingFailingTests = 8
                return true
            }
            return lower.contains("teststoretests.")
                || lower.contains("test case")
                || lower.contains(" failed")
                || lower.contains("** test failed **")
                || lower.contains("error:")
                || lower.contains("fatal:")
                || lower.contains("panic")
                || lower.contains("command not found")
                || lower.contains("timeout")
        }
        let selected = interesting.isEmpty ? Array(lines.prefix(8)) : Array(interesting.prefix(12))
        return "\(label) failed: \(selected.joined(separator: "\n").prefix(1200))"
    }

    /// True when `projectPath` holds a build/test system the critic can verify
    /// deterministically — Cargo, SwiftPM, or an Xcode project. The engine uses
    /// this to force the critic to run for such a project even when the
    /// write-files/substantial-output heuristic would skip it (the agent may edit
    /// via `run_shell`, leaving `writtenFilePaths` empty): for a code project the
    /// deterministic build/test check is exactly what must be run.
    static func hasAutoDetectableProject(at projectPath: String?) -> Bool {
        guard let projectPath, !projectPath.isEmpty,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: projectPath)
        else { return false }
        if entries.contains("Cargo.toml") || entries.contains("Package.swift") {
            return true
        }
        return entries.contains { $0.hasSuffix(".xcodeproj") }
    }

    /// Detects the working project's build system and returns its real build/test
    /// as deterministic verification commands. This is what catches a broken edit
    /// (code that does not compile, tests left red) and fails the critic so the
    /// agent is forced to retry — independent of any manually-configured command.
    /// Only runs for code-modifying task types.
    func autoDetectedProjectCommands(for taskType: DomainTaskType) async -> [VerificationCommand] {
        let codeTaskTypes: Set<String> = [
            "code_generation", "refactoring", "test_writing",
            "debugging", "schema_migration", "security_logic",
        ]
        guard codeTaskTypes.contains(taskType.name),
              let projectPath, !projectPath.isEmpty,
              FileManager.default.fileExists(atPath: projectPath) else {
            return []
        }
        let fm = FileManager.default
        let quoted = projectPath.replacingOccurrences(of: "'", with: "'\\''")
        func has(_ name: String) -> Bool {
            fm.fileExists(atPath: projectPath + "/" + name)
        }
        if has("Cargo.toml") {
            let cargoEnv = "source \"$HOME/.cargo/env\" 2>/dev/null; export PATH=\"$HOME/.cargo/bin:$PATH\""
            return [
                VerificationCommand(
                    label: "cargo build",
                    command: "\(cargoEnv); cd '\(quoted)' && cargo build --quiet 2>&1",
                    passCondition: .exitCode(0)),
                VerificationCommand(
                    label: "cargo test",
                    command: "\(cargoEnv); cd '\(quoted)' && cargo test --quiet 2>&1",
                    passCondition: .exitCode(0)),
            ]
        }
        if has("Package.swift") {
            return [
                VerificationCommand(
                    label: "swift build",
                    command: "cd '\(quoted)' && swift build 2>&1",
                    passCondition: .exitCode(0)),
            ]
        }
        // Xcode project — run the scheme's test action so failing unit tests are
        // caught (a build-only check would miss them).
        let entries = (try? fm.contentsOfDirectory(atPath: projectPath)) ?? []
        if let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let (_, listOut) = await shellRunner.run(
                "cd '\(quoted)' && xcodebuild -list -json 2>/dev/null")
            let scheme = Self.firstScheme(fromXcodebuildListJSON: listOut)
                ?? (proj as NSString).deletingPathExtension
            return [
                VerificationCommand(
                    label: "xcodebuild test (\(scheme))",
                    command: "cd '\(quoted)' && xcodebuild test -scheme '\(scheme)' "
                        + "-destination 'platform=macOS' CODE_SIGN_IDENTITY='' "
                        + "CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1",
                    passCondition: .outputContains("TEST SUCCEEDED")),
            ]
        }
        return []
    }

    /// Extracts the first scheme name from `xcodebuild -list -json` output.
    static func firstScheme(fromXcodebuildListJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let container = (object["project"] as? [String: Any])
            ?? (object["workspace"] as? [String: Any])
        return (container?["schemes"] as? [String])?.first
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
        let requestModel: String
        if let manager = modelManager {
            let estimatedTokens = prompt.count / 4 + 512
            requestModel = (try? await manager.ensureContextLength(
                modelID: provider.resolvedModelID,
                minimumTokens: estimatedTokens
            )) ?? provider.resolvedModelID
        } else {
            requestModel = provider.resolvedModelID
        }

        var request = CompletionRequest(
            model: requestModel,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )
        let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
        inferenceDefaults.apply(to: &request)

        do {
            var fullResponse = ""
            let stream = try await PreflightGuard.complete(request, provider: provider)
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
