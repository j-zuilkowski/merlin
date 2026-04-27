import Foundation

@MainActor
final class ToolRouter {
    private let authGate: AuthGate
    private var handlers: [String: (String) async throws -> String] = [:]

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
        let argument = primaryArgument(from: call.function.arguments)
        let decision = await authGate.check(tool: call.function.name, argument: argument)
        guard decision == .allow else {
            return ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)
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
}
