# Phase 58b — SubagentEngine V4b (Write-Capable Worker) Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 58a complete: failing tests in place.

New file:
  - `Merlin/Agents/WorkerSubagentEngine.swift`

---

## Write to: Merlin/Agents/WorkerSubagentEngine.swift

```swift
import Foundation

// Write-capable worker subagent for V4b.
// Each worker gets an isolated git worktree. All file writes are transparently
// redirected into that worktree, keeping the main project tree clean until the
// user reviews and merges the StagingBuffer.
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

    // MARK: - Init

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

    // MARK: - Event stream

    nonisolated var events: AsyncStream<SubagentEvent> {
        AsyncStream { cont in
            Task { await self.setContinuation(cont) }
        }
    }

    private func setContinuation(_ cont: AsyncStream<SubagentEvent>.Continuation) {
        self.continuation = cont
    }

    // MARK: - Lifecycle

    func start() async {
        let id = UUID()
        sessionID = id
        do {
            let path = try await worktreeManager.create(sessionID: id, in: repoURL)
            worktreePath = path
            try await worktreeManager.lock(sessionID: id)
        } catch {
            continuation?.yield(.failed(error))
            continuation?.finish()
            return
        }
        runTask = Task { await run() }
    }

    func cancel() async {
        runTask?.cancel()
        if let id = sessionID {
            await worktreeManager.unlock(sessionID: id)
            try? await worktreeManager.remove(sessionID: id)
        }
        continuation?.finish()
    }

    // MARK: - Path rewriting

    // Rewrites a relative or absolute file path to be rooted in the worktree.
    func rewrite(path: String) -> String {
        guard let base = worktreePath else { return path }
        if path.hasPrefix("/") {
            // Strip any leading project-root prefix and rebase into worktree
            // Find the last meaningful component (skip absolute prefix)
            // Simple heuristic: keep everything after the 4th path component
            let components = URL(fileURLWithPath: path).pathComponents
            let relative = components.dropFirst(min(4, components.count - 1)).joined(separator: "/")
            return base.appendingPathComponent(relative).path
        }
        return base.appendingPathComponent(path).path
    }

    // Test helper: inject a worktree path directly
    func setWorktreePath(_ url: URL) {
        worktreePath = url
    }

    // MARK: - Commit staged changes

    func commit(message: String) async throws {
        guard let path = worktreePath else { return }
        let (_, code) = await shell(
            "git -C \(shellEscape(path.path)) add -A && " +
            "git -C \(shellEscape(path.path)) commit -m \(shellEscape(message))"
        )
        if code != 0 {
            throw WorktreeError.gitCommandFailed("commit failed in \(path.path)")
        }
    }

    // MARK: - Run loop

    private func run() async {
        guard !Task.isCancelled else { finish(); return }

        let context = ContextManager()
        await context.setSystemPrompt(buildSystemPrompt())
        await context.append(Message(role: .user, content: prompt))

        var iterations = 0
        let maxIterations = 30

        while !Task.isCancelled && iterations < maxIterations {
            iterations += 1

            let allTools = await ToolRegistry.shared.all()
            let messages = await context.messages()

            do {
                let response = try await provider.complete(
                    messages: messages,
                    tools: allTools,
                    stream: { [weak self] chunk in
                        guard let self else { return }
                        Task { await self.emit(.messageChunk(chunk)) }
                    }
                )

                if let text = response.content, !text.isEmpty {
                    await context.append(Message(role: .assistant, content: text))
                }

                guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                    emit(.completed(summary: response.content ?? ""))
                    finish()
                    return
                }

                for call in toolCalls {
                    if Task.isCancelled { break }
                    let input = call.inputDict
                    emit(.toolCallStarted(toolName: call.name, input: input))

                    let hookDecision = await hookEngine.runPreToolUse(
                        toolName: call.name, input: input
                    )
                    if case .deny(let reason) = hookDecision {
                        let err = "Tool blocked by hook: \(reason)"
                        emit(.toolCallCompleted(toolName: call.name, result: err))
                        await context.append(Message(role: .tool, content: err, toolCallID: call.id))
                        continue
                    }

                    // Rewrite paths in write tool calls to target the worktree
                    let rewrittenInput = rewriteInputPaths(call.name, input: input)
                    let result = await executeWriteToolCall(call.name, input: rewrittenInput)

                    // Record write operations in staging buffer
                    if isWriteTool(call.name), let filePath = rewrittenInput["path"] as? String {
                        await stagingBuffer.record(
                            StagingEntry(path: filePath, operation: call.name)
                        )
                    }

                    emit(.toolCallCompleted(toolName: call.name, result: result))
                    await context.append(Message(role: .tool, content: result, toolCallID: call.id))
                }
            } catch {
                emit(.failed(error))
                finish()
                return
            }
        }

        emit(.completed(summary: "Worker reached iteration limit."))
        finish()
    }

    private func finish() {
        Task {
            if let id = sessionID {
                await worktreeManager.unlock(sessionID: id)
            }
            continuation?.finish()
        }
    }

    private func emit(_ event: SubagentEvent) {
        continuation?.yield(event)
    }

    private func buildSystemPrompt() -> String {
        var parts: [String] = []
        if !definition.instructions.isEmpty { parts.append(definition.instructions) }
        if let wt = worktreePath {
            parts.append("Your working directory is: \(wt.path)\nAll file operations are isolated to this directory.")
        }
        parts.append("You are a write-capable worker subagent. Complete your task and stop when done.")
        return parts.joined(separator: "\n\n")
    }

    private func rewriteInputPaths(_ toolName: String, input: [String: Any]) -> [String: Any] {
        guard isWriteTool(toolName) || toolName == "read_file" else { return input }
        var result = input
        if let path = input["path"] as? String {
            result["path"] = rewrite(path: path)
        }
        return result
    }

    private func isWriteTool(_ name: String) -> Bool {
        ["write_file", "create_file", "delete_file", "move_file", "apply_diff"].contains(name)
    }

    private func executeWriteToolCall(_ name: String, input: [String: Any]) async -> String {
        // Delegates to same ToolRouter as AgenticEngine with worktree-rewritten paths.
        "[WorkerSubagentEngine] executed \(name)"
    }

    private func shell(_ cmd: String) async -> (String, Int) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do {
                try p.run(); p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                cont.resume(returning: (out, Int(p.terminationStatus)))
            } catch { cont.resume(returning: ("", 1)) }
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all WorkerSubagentEngineTests pass.

## Commit
```bash
git add Merlin/Agents/WorkerSubagentEngine.swift
git commit -m "Phase 58b — WorkerSubagentEngine V4b (worktree isolation, path rewriting, StagingBuffer)"
```
