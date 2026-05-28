import Foundation

typealias ToolRouterOriginProvider = @MainActor (ToolRoute) -> WorkspaceMessageOrigin

@MainActor
class ToolRouter {
    private let authGate: AuthGate
    private let workspaceRuntime: WorkspaceRuntime
    private var routes: [String: ToolRoute] = [:]
    private var registrationTasks: [String: Task<Void, Never>] = [:]
    private var mcpDefinitions: [ToolDefinition] = []
    private var mcpDomainScopes: [String: String?] = [:]
    private var workspaceDefinitions: [ToolDefinition] = []
    private var workspaceDomainScopes: [String: String?] = [:]
    private var originProvider: ToolRouterOriginProvider
    var stagingBuffer: StagingBuffer?
    var permissionMode: PermissionMode = .ask

    convenience init(authGate: AuthGate) {
        let runtime = try! WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merlin-default-workspace"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-default-runtime-\(UUID().uuidString)")
        )
        self.init(authGate: authGate, workspaceRuntime: runtime)
    }

    init(
        authGate: AuthGate,
        workspaceRuntime: WorkspaceRuntime,
        originProvider: ToolRouterOriginProvider? = nil
    ) {
        self.authGate = authGate
        self.workspaceRuntime = workspaceRuntime
        self.originProvider = originProvider ?? { route in
            WorkspaceMessageOrigin(
                workspaceID: workspaceRuntime.workspaceID,
                sessionID: nil,
                agentID: nil,
                subagentID: nil,
                worktreeID: nil,
                subagentDepth: 0,
                permissionScope: route.requiredPermissionScope,
                activeDomainIDs: SoftwareDomain.defaultActiveDomainIDs
            )
        }
    }

    func dispatch(
        _ calls: [ToolCall],
        stagingBufferOverride: StagingBuffer? = nil,
        permissionModeOverride: PermissionMode? = nil
    ) async -> [ToolResult] {
        await withTaskGroup(of: (Int, ToolResult).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask {
                    let result = await self.dispatchSingle(
                        call,
                        stagingBufferOverride: stagingBufferOverride,
                        permissionModeOverride: permissionModeOverride
                    )
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
        register(
            name: name,
            namespace: namespace(for: name),
            capability: name,
            timeout: timeout(for: name),
            requiredScope: requiredScope(for: name),
            handler: handler
        )
    }

    func register(
        name: String,
        namespace: String,
        capability: String,
        timeout: Duration? = nil,
        requiredScope: WorkspacePermissionScope = .readOnly,
        handler: @escaping (String) async throws -> String
    ) {
        let route = ToolRoute(
            toolName: name,
            address: WorkspaceMessageAddress(namespace: namespace, capability: capability),
            timeout: timeout ?? self.timeout(for: name),
            requiredPermissionScope: requiredScope
        )
        routes[name] = route
        registrationTasks[name] = Task {
            await workspaceRuntime.bus.register(
                ClosureWorkspaceMessageHandler(requiredScope: requiredScope, handler: handler),
                for: route.address
            )
        }
    }

    func route(for toolName: String) -> ToolRoute? {
        routes[toolName]
    }

    func registeredRoutes() -> [ToolRoute] {
        routes.values.sorted { $0.toolName < $1.toolName }
    }

    func registerMCPTool(_ definition: ToolDefinition,
                         scopedToDomainID domainID: String? = nil,
                         handler: @MainActor @escaping ([String: Any]) async -> String) {
        let name = definition.function.name
        if let existing = mcpDefinitions.firstIndex(where: { $0.function.name == name }) {
            mcpDefinitions[existing] = definition
        } else {
            mcpDefinitions.append(definition)
        }
        mcpDomainScopes[name] = domainID
        let serverName = Self.mcpServerName(fromToolName: name) ?? "unknown"
        register(
            name: name,
            namespace: "mcp.\(serverName)",
            capability: name,
            timeout: .seconds(120),
            requiredScope: .externalSideEffect
        ) { arguments in
            await handler(Self.dictionary(from: arguments))
        }
    }

    func unregisterMCPTools(named names: some Sequence<String>) {
        let nameSet = Set(names)
        mcpDefinitions.removeAll { nameSet.contains($0.function.name) }
        for name in nameSet {
            if let route = routes[name] {
                Task { await workspaceRuntime.bus.unregister(address: route.address) }
            }
            routes.removeValue(forKey: name)
            registrationTasks.removeValue(forKey: name)
            mcpDomainScopes.removeValue(forKey: name)
        }
    }

    func registerWorkspaceCapabilityTools(_ capabilities: [WorkspaceCapability]) {
        for capability in capabilities where capability.kind == .tool || capability.kind == .workflow {
            let name = capability.address.capability
            let definition = Self.definition(for: capability)
            if let existing = workspaceDefinitions.firstIndex(where: { $0.function.name == name }) {
                workspaceDefinitions[existing] = definition
            } else {
                workspaceDefinitions.append(definition)
            }
            workspaceDomainScopes[name] = Self.domainScope(for: capability.address.namespace)
            routes[name] = ToolRoute(
                toolName: name,
                address: capability.address,
                timeout: timeout(for: name),
                requiredPermissionScope: capability.requiredPermissionScope
            )
        }
    }

    func registerKiCadTools(executor: any KiCadToolExecutor) {
        for toolName in KiCadToolDefinitions.requiredToolNames {
            register(name: toolName, namespace: "domain.electronics", capability: toolName, requiredScope: .externalSideEffect) { argumentsJSON in
                let result = try await executor.execute(toolName: toolName, argumentsJSON: argumentsJSON)
                let data = try JSONEncoder().encode(result)
                return String(data: data, encoding: .utf8) ?? "{}"
            }
        }
    }

    func mcpToolDefinitions() -> [ToolDefinition] {
        mcpDefinitions
    }

    func mcpToolDefinitions(activeDomainIDs: [String]) -> [ToolDefinition] {
        mcpDefinitions.filter { isAllowedMCPTool(named: $0.function.name, activeDomainIDs: activeDomainIDs) }
    }

    func workspaceToolDefinitions(activeDomainIDs: [String]) -> [ToolDefinition] {
        workspaceDefinitions.filter { definition in
            guard let scope = workspaceDomainScopes[definition.function.name] else { return true }
            guard let scope else { return true }
            return activeDomainIDs.contains(scope)
        }
    }

    func connectedMCPServerNames(activeDomainIDs: [String]) -> Set<String> {
        Set(mcpToolDefinitions(activeDomainIDs: activeDomainIDs).compactMap { definition in
            Self.mcpServerName(fromToolName: definition.function.name)
        })
    }

    func isAllowedMCPTool(named toolName: String, activeDomainIDs: [String]) -> Bool {
        guard let scope = mcpDomainScopes[toolName] else { return true }
        guard let scope else { return true }
        return activeDomainIDs.contains(scope)
    }

    func hasScopedMCPTools(activeDomainIDs: [String]) -> Bool {
        mcpDefinitions.contains { mcpDomainScopes[$0.function.name] != nil }
            && !mcpToolDefinitions(activeDomainIDs: activeDomainIDs).isEmpty
    }

    func hasWorkspaceTools(activeDomainIDs: [String]) -> Bool {
        !workspaceToolDefinitions(activeDomainIDs: activeDomainIDs).isEmpty
    }

    private func dispatchSingle(
        _ call: ToolCall,
        stagingBufferOverride: StagingBuffer?,
        permissionModeOverride: PermissionMode?
    ) async -> ToolResult {
        let effectiveStagingBuffer = stagingBufferOverride ?? stagingBuffer
        let effectivePermissionMode = permissionModeOverride ?? permissionMode

        if shouldStage(call.function.name,
                       stagingBuffer: effectiveStagingBuffer,
                       permissionMode: effectivePermissionMode) {
            return await stageFileWrite(call: call, buffer: effectiveStagingBuffer)
        }

        let toolName = call.function.name
        guard let route = routes[toolName] else {
            return ToolResult(toolCallId: call.id, content: "ROUTE_NOT_FOUND: Unknown tool: \(toolName)", isError: true)
        }

        let argument = primaryArgument(from: call.function.arguments)
        if effectivePermissionMode != .autoAccept {
            let decision = await authGate.check(tool: toolName, argument: argument)
            guard decision == .allow else {
                return ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)
            }
        }

        await registrationTasks[toolName]?.value
        let request = WorkspaceMessageRequest(
            id: UUID(),
            address: route.address,
            origin: originProvider(route),
            payload: .jsonString(call.function.arguments),
            cancellationGroup: nil
        )
        let first = await workspaceRuntime.bus.send(request, timeout: route.timeout)
        if first.status == .failed {
            authGate.reportFailure(tool: toolName, argument: argument)
            let retry = await workspaceRuntime.bus.send(request, timeout: route.timeout)
            return toolResult(from: retry, toolCallID: call.id)
        }
        return toolResult(from: first, toolCallID: call.id)
    }

    private func toolResult(from response: WorkspaceMessageResponse, toolCallID: String) -> ToolResult {
        switch response.status {
        case .ok:
            return ToolResult(toolCallId: toolCallID, content: response.payload?.stringValue() ?? "", isError: false)
        case .blocked, .failed, .cancelled, .timedOut, .unauthorized:
            let diagnosticText = response.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            return ToolResult(toolCallId: toolCallID, content: diagnosticText.isEmpty ? response.status.rawValue : diagnosticText, isError: true)
        }
    }

    private static func definition(for capability: WorkspaceCapability) -> ToolDefinition {
        if let kicad = KiCadToolDefinitions.all.first(where: { $0.function.name == capability.address.capability }) {
            return kicad
        }
        if capability.address.namespace == "plugin.electronics",
           (capability.address.capability == "workflow.requirements_to_pcb"
            || capability.address.capability == "workflow.schematic_to_pcb") {
            let description: String
            if capability.address.capability == "workflow.requirements_to_pcb" {
                description = "Run the complete verified electronics flow from natural-language requirements to KiCad schematic, PCB, routing, simulation evidence, fabrication artifacts, and final gate report. Use this as the first tool for end-to-end board design requests."
            } else {
                description = "Run the complete verified electronics flow from an existing schematic to PCB layout, routing, simulation evidence, fabrication artifacts, and final gate report."
            }
            return ToolDefinition(function: .init(
                name: capability.address.capability,
                description: description,
                parameters: JSONSchema(type: "object", properties: [
                    "job_id": JSONSchema(type: "string", description: "Stable electronics job id"),
                    "requirements": JSONSchema(type: "string", description: "Natural-language board requirements"),
                    "output_directory": JSONSchema(type: "string", description: "Optional output directory for generated KiCad artifacts"),
                    "high_stakes": JSONSchema(type: "boolean", description: "Whether the workflow needs explicit signoff before release"),
                ], required: ["requirements"])
            ))
        }
        return ToolDefinition(function: .init(
            name: capability.address.capability,
            description: capability.displayName,
            parameters: JSONSchema(type: "object")
        ))
    }

    private static func domainScope(for namespace: String) -> String? {
        if namespace == "plugin.electronics" || namespace == "domain.electronics" {
            return ElectronicsDomain.defaultID
        }
        return nil
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

    private func shouldStage(
        _ toolName: String,
        stagingBuffer: StagingBuffer?,
        permissionMode: PermissionMode
    ) -> Bool {
        guard stagingBuffer != nil else { return false }
        guard permissionMode == .ask || permissionMode == .plan else { return false }
        return isFileWriteTool(toolName)
    }

    private func stageFileWrite(call: ToolCall, buffer: StagingBuffer?) async -> ToolResult {
        guard let buffer else {
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
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }

    private func namespace(for toolName: String) -> String {
        switch toolName {
        case "read_file", "write_file", "create_file", "delete_file", "list_directory", "move_file", "search_files":
            return "builtin.files"
        case "run_shell", "bash":
            return "builtin.shell"
        case let name where name.hasPrefix("xcode_"):
            return "builtin.xcode"
        case let name where name.hasPrefix("ui_") || name == "vision_query":
            return "builtin.ui"
        case let name where name.hasPrefix("app_"):
            return "builtin.app"
        case "rag_search", "rag_list_books":
            return "builtin.knowledge"
        case "generate_api_docs", "generate_dev_guide", "write_vale_styles", "scaffold_manual_coverage":
            return "builtin.discipline"
        case "tool_discover":
            return "builtin.app"
        default:
            return "builtin.tools"
        }
    }

    private func requiredScope(for toolName: String) -> WorkspacePermissionScope {
        switch toolName {
        case "read_file", "list_directory", "search_files", "tool_discover", "rag_search", "rag_list_books":
            return .readOnly
        case "write_file", "create_file", "delete_file", "move_file", "generate_api_docs", "generate_dev_guide", "write_vale_styles", "scaffold_manual_coverage":
            return .workspaceWrite
        case "app_launch", "app_quit", "app_focus", "run_shell", "bash":
            return .externalSideEffect
        default:
            return .externalSideEffect
        }
    }

    private func timeout(for toolName: String) -> Duration {
        if toolName.hasPrefix("xcode_") {
            return .seconds(600)
        }
        return .seconds(120)
    }

    private static func dictionary(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func mcpServerName(fromToolName name: String) -> String? {
        let parts = name.split(separator: ":")
        return parts.count >= 3 ? String(parts[1]) : nil
    }
}
