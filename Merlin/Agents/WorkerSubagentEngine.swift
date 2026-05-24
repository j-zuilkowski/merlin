import Foundation

actor WorkerSubagentEngine {

    private let definition: AgentDefinition
    private let prompt: String
    private let provider: any LLMProvider
    private let fallbackModel: String
    private let hookEngine: HookEngine
    private let depth: Int
    private let worktreeManager: WorktreeManager
    private let repoURL: URL
    private let toolDefinitionsProvider: SubagentToolDefinitionsProvider
    private let toolExecutor: SubagentToolExecutor

    private(set) var worktreePath: URL?
    private(set) var sessionID: UUID?
    let stagingBuffer: StagingBuffer

    private var runTask: Task<Void, Never>?
    private var continuation: AsyncStream<SubagentEvent>.Continuation?
    private var pendingEvents: [SubagentEvent] = []

    init(
        definition: AgentDefinition,
        prompt: String,
        provider: any LLMProvider,
        fallbackModel: String = "",
        hookEngine: HookEngine,
        depth: Int,
        worktreeManager: WorktreeManager,
        repoURL: URL,
        stagingBuffer: StagingBuffer = StagingBuffer(),
        toolDefinitionsProvider: @escaping SubagentToolDefinitionsProvider = { ToolRegistry.shared.all() },
        toolExecutor: @escaping SubagentToolExecutor = { call in
            ToolResult(
                toolCallId: call.id,
                content: "Unknown tool: \(call.function.name)",
                isError: true
            )
        }
    ) {
        self.definition = definition
        self.prompt = prompt
        self.provider = provider
        self.fallbackModel = fallbackModel
        self.hookEngine = hookEngine
        self.depth = depth
        self.worktreeManager = worktreeManager
        self.repoURL = repoURL
        self.stagingBuffer = stagingBuffer
        self.toolDefinitionsProvider = toolDefinitionsProvider
        self.toolExecutor = toolExecutor
    }

    nonisolated var events: AsyncStream<SubagentEvent> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    private func setContinuation(_ continuation: AsyncStream<SubagentEvent>.Continuation) {
        self.continuation = continuation
        for event in pendingEvents {
            continuation.yield(event)
        }
        pendingEvents.removeAll()
    }

    func start() async {
        let sessionID = UUID()
        self.sessionID = sessionID

        do {
            let worktree = try await worktreeManager.create(sessionID: sessionID, in: repoURL)
            worktreePath = worktree
            try await worktreeManager.lock(sessionID: sessionID)
            yield(.workerReady(worktreePath: worktree, stagingBuffer: stagingBuffer))
        } catch {
            yield(.failed(error))
            continuation?.finish()
            return
        }

        runTask = Task {
            await run()
        }
    }

    func cancel() async {
        runTask?.cancel()
        if let sessionID {
            await worktreeManager.unlock(sessionID: sessionID)
            try? await worktreeManager.remove(sessionID: sessionID)
        }
        continuation?.finish()
    }

    func rewrite(path: String) async -> String {
        guard let worktreePath else {
            return path
        }

        if path.hasPrefix("/") {
            let repoPrefix = repoURL.path.hasSuffix("/") ? repoURL.path : repoURL.path + "/"
            if path.hasPrefix(repoPrefix) {
                let relativeToRepo = String(path.dropFirst(repoPrefix.count))
                return worktreePath.appendingPathComponent(relativeToRepo).path
            }
            let relative = path.trimmingPrefix("/")
            return worktreePath.appendingPathComponent(relative).path
        }

        return worktreePath.appendingPathComponent(path).path
    }

    func setWorktreePath(_ url: URL) async {
        worktreePath = url
    }

    func commit(message: String) async throws {
        guard let worktreePath else {
            return
        }

        let command = "git -C \(shellEscape(worktreePath.path)) add -A && git -C \(shellEscape(worktreePath.path)) commit -m \(shellEscape(message))"
        let result = await shell(command)
        guard result.exitCode == 0 else {
            throw WorktreeError.gitCommandFailed(result.output)
        }
    }

    private func run() async {
        guard Task.isCancelled == false else {
            finish()
            return
        }

        let context = await MainActor.run { ContextManager() }
        await context.append(Message(role: .system, content: .text(buildSystemPrompt()), timestamp: Date()))
        await context.append(Message(role: .user, content: .text(prompt), timestamp: Date()))

        var iterations = 0
        let maxIterations = 30

        while Task.isCancelled == false, iterations < maxIterations {
            iterations += 1

            var request = CompletionRequest(
                model: definition.model ?? fallbackModel,
                messages: await context.messagesForProvider(),
                tools: await availableTools(),
                stream: true,
                thinking: nil,
                maxTokens: nil,
                temperature: nil
            )
            let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
            inferenceDefaults.apply(to: &request)

            do {
                let stream = try await PreflightGuard.complete(request, provider: provider)
                var responseText = ""
                var thinkingText = ""
                var assembler = StreamedToolCallAssembler()
                for try await chunk in stream {
                    if let text = chunk.delta?.content, text.isEmpty == false {
                        responseText += text
                        yield(.messageChunk(text))
                    }
                    if let thinking = chunk.delta?.thinkingContent, thinking.isEmpty == false {
                        thinkingText += thinking
                    }

                    if let toolCalls = chunk.delta?.toolCalls {
                        assembler.append(toolCalls)
                    }
                }

                let calls = assembler.calls
                if calls.isEmpty == false {
                    await context.append(Message(
                        role: .assistant,
                        content: .text(responseText),
                        toolCalls: calls,
                        thinkingContent: thinkingText.isEmpty ? nil : thinkingText,
                        timestamp: Date()
                    ))
                    await executeToolCalls(calls, into: context)
                    continue
                }

                await context.append(Message(
                    role: .assistant,
                    content: .text(responseText),
                    thinkingContent: thinkingText.isEmpty ? nil : thinkingText,
                    timestamp: Date()
                ))
                await complete(summary: responseText)
                return
            } catch {
                yield(.failed(error))
                continuation?.finish()
                return
            }
        }

        await complete(summary: "Worker reached iteration limit.")
    }

    private func complete(summary: String) async {
        await stageWorktreeDiff()
        yield(.completed(summary: summary))
        continuation?.finish()
    }

    private func finish() {
        Task { [sessionID] in
            if let sessionID {
                await worktreeManager.unlock(sessionID: sessionID)
            }
            continuation?.finish()
        }
    }

    private func yield(_ event: SubagentEvent) {
        if let continuation {
            continuation.yield(event)
        } else {
            pendingEvents.append(event)
        }
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []
        if definition.instructions.isEmpty == false {
            parts.append(definition.instructions)
        }
        if let worktreePath {
            parts.append("Your working directory is: \(worktreePath.path)\nAll file operations are isolated to this directory.")
        }
        parts.append("You are a write-capable worker subagent. Complete your task and stop when done.")
        return parts.joined(separator: "\n\n")
    }

    private func availableTools() async -> [ToolDefinition] {
        let names = Set(availableToolNames())
        let tools = await toolDefinitionsProvider()
        return tools.filter { names.contains($0.function.name) }
    }

    private func availableToolNames() -> [String] {
        switch definition.role {
        case .explorer:
            return definition.allowedTools ?? AgentDefinition.explorerToolSet
        case .worker, .default:
            return definition.allowedTools ?? ToolDefinitions.all.map { $0.function.name }
        }
    }

    private func executeToolCalls(_ calls: [ToolCall], into context: ContextManager) async {
        for call in calls {
            let input = inputDictionary(from: call.function.arguments)
            yield(.toolCallStarted(toolName: call.function.name, input: input))

            let result: ToolResult
            if call.function.name == "spawn_agent" {
                result = ToolResult(
                    toolCallId: call.id,
                    content: "spawn_agent is not supported from inside a worker subagent yet. Complete the remaining work yourself.",
                    isError: true
                )
            } else {
                let hookDecision = await hookEngine.runPreToolUse(
                    toolName: call.function.name,
                    input: input
                )
                switch hookDecision {
                case .allow:
                    result = await executeToolCall(call)
                case .deny(let reason):
                    result = ToolResult(
                        toolCallId: call.id,
                        content: "Tool blocked by hook: \(reason)",
                        isError: true
                    )
                }
            }

            yield(.toolCallCompleted(toolName: call.function.name, result: result.content))
            await context.append(Message(
                role: .tool,
                content: .text(result.content),
                toolCallId: call.id,
                timestamp: Date()
            ))

            if let note = await hookEngine.runPostToolUse(
                toolName: call.function.name,
                result: result.content
            ) {
                await context.append(Message(role: .system, content: .text(note), timestamp: Date()))
            }
        }
    }

    private func executeToolCall(_ call: ToolCall) async -> ToolResult {
        let rewrittenArguments = await rewriteArguments(call.function.arguments, for: call.function.name)
        let rewrittenCall = ToolCall(
            id: call.id,
            type: call.type,
            function: FunctionCall(name: call.function.name, arguments: rewrittenArguments)
        )
        return await toolExecutor(rewrittenCall)
    }

    private func rewriteArguments(_ arguments: String, for toolName: String) async -> String {
        guard let data = arguments.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments
        }

        for key in ["path", "src", "dst", "source_path", "destination_path", "cwd"] {
            if let value = object[key] as? String {
                object[key] = await rewrite(path: value)
            }
        }
        if isShellTool(toolName), let worktreePath {
            if object["cwd"] == nil {
                object["cwd"] = worktreePath.path
            }
            if let command = object["command"] as? String {
                object["command"] = rewriteShellCommand(command, worktreePath: worktreePath)
            }
        }

        guard let rewritten = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: rewritten, encoding: .utf8) else {
            return arguments
        }
        return json
    }

    private func inputDictionary(from arguments: String) -> [String: String] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }

    private func isShellTool(_ name: String) -> Bool {
        name == "run_shell" || name == "bash"
    }

    private func rewriteShellCommand(_ command: String, worktreePath: URL) -> String {
        let repoPath = repoURL.path
        guard command.contains(repoPath) else {
            return command
        }
        return command.replacingOccurrences(of: repoPath, with: worktreePath.path)
    }

    private func stageWorktreeDiff() async {
        guard let worktreePath else { return }
        let result = await shell(
            "git -C \(shellEscape(worktreePath.path)) status --porcelain -z --untracked-files=all"
        )
        guard result.exitCode == 0, result.output.isEmpty == false else { return }

        for path in changedPaths(fromPorcelainZ: result.output) {
            let worktreeFile = worktreePath.appendingPathComponent(path)
            let repoFile = repoURL.appendingPathComponent(path)
            let beforeExists = FileManager.default.fileExists(atPath: repoFile.path)
            let afterExists = FileManager.default.fileExists(atPath: worktreeFile.path)
            let before = beforeExists ? try? String(contentsOf: repoFile, encoding: .utf8) : nil
            let after = afterExists ? try? String(contentsOf: worktreeFile, encoding: .utf8) : nil
            let kind: ChangeKind
            if beforeExists == false, afterExists {
                kind = .create
            } else if beforeExists, afterExists == false {
                kind = .delete
            } else {
                kind = .write
            }
            await stagingBuffer.stage(StagedChange(
                path: repoFile.path,
                kind: kind,
                before: before,
                after: after,
                destinationPath: nil
            ))
        }
    }

    private func changedPaths(fromPorcelainZ output: String) -> [String] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var paths: [String] = []
        var index = 0
        while index < fields.count {
            let entry = String(fields[index])
            let status = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            if status.contains("R") || status.contains("C") {
                if index + 1 < fields.count {
                    paths.append(String(fields[index + 1]))
                    index += 2
                    continue
                }
            }
            if path.isEmpty == false {
                paths.append(path)
            }
            index += 1
        }
        return Array(Set(paths)).sorted()
    }

    private func shell(_ command: String) async -> (output: String, exitCode: Int) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, Int(process.terminationStatus)))
            } catch {
                continuation.resume(returning: ("\(error)", 1))
            }
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
