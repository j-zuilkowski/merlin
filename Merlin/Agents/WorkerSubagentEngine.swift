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
    let stagingBuffer = StagingBuffer()

    private var runTask: Task<Void, Never>?
    private var continuation: AsyncStream<SubagentEvent>.Continuation?

    init(
        definition: AgentDefinition,
        prompt: String,
        provider: any LLMProvider,
        fallbackModel: String = "",
        hookEngine: HookEngine,
        depth: Int,
        worktreeManager: WorktreeManager,
        repoURL: URL,
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
    }

    func start() async {
        let sessionID = UUID()
        self.sessionID = sessionID

        do {
            let worktree = try await worktreeManager.create(sessionID: sessionID, in: repoURL)
            worktreePath = worktree
            try await worktreeManager.lock(sessionID: sessionID)
        } catch {
            continuation?.yield(.failed(error))
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
                        continuation?.yield(.messageChunk(text))
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
                continuation?.yield(.completed(summary: responseText))
                continuation?.finish()
                return
            } catch {
                continuation?.yield(.failed(error))
                continuation?.finish()
                return
            }
        }

        continuation?.yield(.completed(summary: "Worker reached iteration limit."))
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
            continuation?.yield(.toolCallStarted(toolName: call.function.name, input: input))

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

            continuation?.yield(.toolCallCompleted(toolName: call.function.name, result: result.content))
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
        let rewrittenInput = inputDictionary(from: rewrittenArguments)

        if isWriteTool(call.function.name), let path = rewrittenInput["path"] {
            await stagingBuffer.record(StagingEntry(path: path, operation: call.function.name))
        }
        if let source = rewrittenInput["src"] ?? rewrittenInput["source_path"] {
            await stagingBuffer.record(StagingEntry(path: source, operation: call.function.name))
        }
        if let destination = rewrittenInput["dst"] ?? rewrittenInput["destination_path"] {
            await stagingBuffer.record(StagingEntry(path: destination, operation: call.function.name))
        }

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
        if (toolName == "run_shell" || toolName == "bash"),
           object["cwd"] == nil,
           let worktreePath {
            object["cwd"] = worktreePath.path
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

    private func isWriteTool(_ name: String) -> Bool {
        ["write_file", "create_file", "delete_file", "move_file", "apply_diff"].contains(name)
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
