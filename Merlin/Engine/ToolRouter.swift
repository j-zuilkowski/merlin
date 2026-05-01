// ToolRouter — dispatches tool calls from AgenticEngine to registered handlers.
//
// Responsibilities (in order):
//   1. Decide whether to stage a file-write call instead of executing it (Plan mode)
//   2. Run AuthGate to check allow/deny patterns and surface the auth popup if needed
//   3. Route to the correct handler (local registry or MCP)
//   4. Retry once on failure before returning an error result
//
// All calls in a single LLM response are dispatched in parallel via TaskGroup.
//
// See: Developer Manual § "Tool System → ToolRouter"
import Foundation

@MainActor
class ToolRouter {
    private let authGate: AuthGate
    private var handlers: [String: (String) async throws -> String] = [:]
    private var mcpHandlers: [String: (String) async throws -> String] = [:]
    private var mcpDefinitions: [ToolDefinition] = []
    var stagingBuffer: StagingBuffer?
    var permissionMode: PermissionMode = .ask

    init(authGate: AuthGate) {
        self.authGate = authGate
    }

    func dispatch(_ calls: [ToolCall]) async -> [ToolResult] {
        await withTaskGroup(of: (Int, ToolResult).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask {
                    let result = await self.dispatchSingle(call)
                    return (index, result)
                }
            }

            var ordered: [(Int, ToolResult)] = []
            for await pair in group {
                ordered.append(pair)
            }
            ordered.sort { $0.0 < $1.0 }
            return ordered.map { $0.1 }
        }
    }

    func register(name: String, handler: @escaping (String) async throws -> String) {
        handlers[name] = handler
    }

    func registerMCPTool(_ definition: ToolDefinition,
                         handler: @MainActor @escaping ([String: Any]) async -> String) {
        let name = definition.function.name
        mcpDefinitions.append(definition)
        mcpHandlers[name] = { arguments in
            await handler(Self.dictionary(from: arguments))
        }
    }

    func mcpToolDefinitions() -> [ToolDefinition] {
        mcpDefinitions
    }

    private func dispatchSingle(_ call: ToolCall) async -> ToolResult {
        if shouldStage(call.function.name) {
            return await stageFileWrite(call: call)
        }

        let argument = primaryArgument(from: call.function.arguments)
        if permissionMode != .autoAccept {
            let decision = await authGate.check(tool: call.function.name, argument: argument)
            guard decision == .allow else {
                return ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)
            }
        }

        let toolName = call.function.name
        let handler: ((String) async throws -> String)?
        if let mcpHandler = mcpHandlers[toolName] {
            handler = mcpHandler
        } else {
            handler = handlers[toolName]
        }

        guard let handler else {
            return ToolResult(toolCallId: call.id, content: "Unknown tool: \(call.function.name)", isError: true)
        }

        do {
            let output = try await handler(call.function.arguments)
            return ToolResult(toolCallId: call.id, content: output, isError: false)
        } catch {
            authGate.reportFailure(tool: call.function.name, argument: argument)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let output = try await handler(call.function.arguments)
                return ToolResult(toolCallId: call.id, content: output, isError: false)
            } catch {
                return ToolResult(toolCallId: call.id, content: String(describing: error), isError: true)
            }
        }
    }

    private func primaryArgument(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }

        for key in ["path", "command", "bundle_id", "src", "udid"] {
            if let value = obj[key] as? String {
                return value
            }
        }
        return obj.values.compactMap { $0 as? String }.first ?? json
    }

    private func isFileWriteTool(_ name: String) -> Bool {
        ["write_file", "create_file", "delete_file", "move_file"].contains(name)
    }

    // Stage instead of execute when: a staging buffer is attached (Plan mode) AND
    // the tool mutates the file system. The buffer shows the diff in the DiffPane
    // for user review before any bytes hit disk.
    private func shouldStage(_ toolName: String) -> Bool {
        guard stagingBuffer != nil else { return false }
        guard permissionMode == .ask || permissionMode == .plan else { return false }
        return isFileWriteTool(toolName)
    }

    private func stageFileWrite(call: ToolCall) async -> ToolResult {
        guard let buffer = stagingBuffer else {
            return ToolResult(toolCallId: call.id, content: "error: no staging buffer", isError: true)
        }

        let args = stringArguments(from: call.function.arguments)
        let path = args["path"] ?? args["source_path"] ?? args["src"] ?? ""
        let kind = changeKind(for: call.function.name)
        let before = path.isEmpty ? nil : (try? String(contentsOfFile: path, encoding: .utf8))
        let change = StagedChange(
            path: path,
            kind: kind,
            before: before,
            after: args["content"] ?? args["new_content"],
            destinationPath: args["destination_path"] ?? args["dst"]
        )
        await buffer.stage(change)
        return ToolResult(
            toolCallId: call.id,
            content: "Staged \(kind.rawValue) for \(path) — awaiting review",
            isError: false
        )
    }

    private func changeKind(for toolName: String) -> ChangeKind {
        switch toolName {
        case "create_file":
            return .create
        case "delete_file":
            return .delete
        case "move_file":
            return .move
        default:
            return .write
        }
    }

    private func stringArguments(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        guard let dictionary = jsonObject as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }

    private static func dictionary(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}
