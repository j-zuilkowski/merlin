import Foundation

@MainActor
final class ToolRouter {
    private let authGate: AuthGate
    private var handlers: [String: (String) async throws -> String] = [:]
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

    private func dispatchSingle(_ call: ToolCall) async -> ToolResult {
        if shouldStage(call.function.name) {
            return await stageFileWrite(call: call)
        }

        let argument = primaryArgument(from: call.function.arguments)
        if !(permissionMode == .autoAccept && isFileWriteTool(call.function.name)) {
            let decision = await authGate.check(tool: call.function.name, argument: argument)
            guard decision == .allow else {
                return ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)
            }
        }

        guard let handler = handlers[call.function.name] else {
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

    private func shouldStage(_ toolName: String) -> Bool {
        guard stagingBuffer != nil else { return false }
        guard permissionMode == .ask || permissionMode == .plan else { return false }
        return isFileWriteTool(toolName)
    }

    private func stageFileWrite(call: ToolCall) async -> ToolResult {
        guard let buffer = stagingBuffer else {
            return ToolResult(toolCallId: call.id, content: "error: no staging buffer", isError: true)
        }

        do {
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
        } catch {
            return ToolResult(toolCallId: call.id, content: "staging error: \(error)", isError: true)
        }
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
}
