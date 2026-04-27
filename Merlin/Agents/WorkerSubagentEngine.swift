import Foundation

actor WorkerSubagentEngine {

    private let definition: AgentDefinition
    private let prompt: String
    private let provider: any LLMProvider
    private let hookEngine: HookEngine
    private let depth: Int
    private let worktreeManager: WorktreeManager
    private let repoURL: URL

    private(set) var worktreePath: URL?
    private(set) var sessionID: UUID?
    let stagingBuffer = StagingBuffer()

    private var runTask: Task<Void, Never>?
    private var continuation: AsyncStream<SubagentEvent>.Continuation?

    init(
        definition: AgentDefinition,
        prompt: String,
        provider: any LLMProvider,
        hookEngine: HookEngine,
        depth: Int,
        worktreeManager: WorktreeManager,
        repoURL: URL
    ) {
        self.definition = definition
        self.prompt = prompt
        self.provider = provider
        self.hookEngine = hookEngine
        self.depth = depth
        self.worktreeManager = worktreeManager
        self.repoURL = repoURL
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

            let request = CompletionRequest(
                model: definition.model ?? "",
                messages: await context.messagesForProvider(),
                tools: await availableTools(),
                stream: true,
                thinking: nil,
                maxTokens: nil,
                temperature: nil
            )

            do {
                let stream = try await provider.complete(request: request)
                var responseText = ""
                for try await chunk in stream {
                    if let text = chunk.delta?.content, text.isEmpty == false {
                        responseText += text
                        continuation?.yield(.messageChunk(text))
                    }

                    if let toolCalls = chunk.delta?.toolCalls {
                        for call in toolCalls {
                            guard let function = call.function,
                                  let name = function.name,
                                  let arguments = function.arguments else {
                                continue
                            }

                            let input = inputDictionary(from: arguments)
                            continuation?.yield(.toolCallStarted(toolName: name, input: input))

                            let hookDecision = await hookEngine.runPreToolUse(toolName: name, input: input)
                            if case .deny(let reason) = hookDecision {
                                let blocked = "Tool blocked by hook: \(reason)"
                                continuation?.yield(.toolCallCompleted(toolName: name, result: blocked))
                                await context.append(Message(role: .tool, content: .text(blocked), toolCallId: call.id, timestamp: Date()))
                                continue
                            }

                            let result = await executeToolCall(name, input: input)
                            continuation?.yield(.toolCallCompleted(toolName: name, result: result))
                            await context.append(Message(role: .tool, content: .text(result), toolCallId: call.id, timestamp: Date()))
                        }
                    }
                }

                if responseText.isEmpty == false {
                    await context.append(Message(role: .assistant, content: .text(responseText), timestamp: Date()))
                }

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
        await ToolRegistry.shared.all()
    }

    private func executeToolCall(_ name: String, input: [String: String]) async -> String {
        if isWriteTool(name), let path = input["path"] {
            await stagingBuffer.record(StagingEntry(path: path, operation: name))
        }
        if let source = input["src"] {
            await stagingBuffer.record(StagingEntry(path: source, operation: name))
        }
        if let destination = input["dst"] {
            await stagingBuffer.record(StagingEntry(path: destination, operation: name))
        }
        return "[WorkerSubagentEngine] executed \(name)"
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
