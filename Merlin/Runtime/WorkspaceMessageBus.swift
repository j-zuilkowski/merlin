import Foundation

actor WorkspaceMessageBus {
    private struct Subscriber {
        var filter: WorkspaceMessageEventFilter
        var continuation: AsyncStream<WorkspaceMessageEvent>.Continuation
    }

    let workspaceID: String
    let workspaceRoot: URL
    let settingsRootURL: URL?

    private var handlers: [WorkspaceMessageAddress: any WorkspaceMessageHandler] = [:]
    private var capabilities: [WorkspaceCapability] = []
    private var settingsSchemas: [WorkspaceSettingsSchema] = []
    private var cancelledRequestIDs: Set<UUID> = []
    private var eventBuffer: [WorkspaceMessageEvent] = []
    private var subscribers: [UUID: Subscriber] = [:]
    private var eventCapacity: Int

    init(workspaceID: String, workspaceRoot: URL, settingsRootURL: URL? = nil, eventCapacity: Int = 1_000) {
        self.workspaceID = workspaceID
        self.workspaceRoot = workspaceRoot
        self.settingsRootURL = settingsRootURL
        self.eventCapacity = WorkspaceRuntime.clampedEventCapacity(eventCapacity)
    }

    func register(_ handler: any WorkspaceMessageHandler, for address: WorkspaceMessageAddress) {
        handlers[address] = handler
    }

    func unregister(address: WorkspaceMessageAddress) {
        handlers.removeValue(forKey: address)
        capabilities.removeAll { $0.address == address }
    }

    func hasRoute(_ address: WorkspaceMessageAddress) -> Bool {
        handlers[address] != nil
    }

    func registeredAddresses() -> [WorkspaceMessageAddress] {
        handlers.keys.sorted { $0.description < $1.description }
    }

    func registerCapability(_ capability: WorkspaceCapability) {
        capabilities.removeAll { $0.id == capability.id || $0.address == capability.address }
        capabilities.append(capability)
    }

    func registeredCapabilities() -> [WorkspaceCapability] {
        capabilities.sorted { $0.id < $1.id }
    }

    func registerSettingsSchema(_ schema: WorkspaceSettingsSchema) {
        settingsSchemas.removeAll { $0.namespace == schema.namespace }
        settingsSchemas.append(schema)
    }

    func registeredSettingsSchemas() -> [WorkspaceSettingsSchema] {
        settingsSchemas.sorted { $0.namespace < $1.namespace }
    }

    func setEventCapacity(_ capacity: Int) {
        eventCapacity = WorkspaceRuntime.clampedEventCapacity(capacity)
        trimEventBuffer()
    }

    func recentEvents(matching filter: WorkspaceMessageEventFilter = WorkspaceMessageEventFilter()) -> [WorkspaceMessageEvent] {
        eventBuffer.filter { filter.matches($0) }
    }

    func send(_ request: WorkspaceMessageRequest, timeout: Duration? = nil) async -> WorkspaceMessageResponse {
        guard cancelledRequestIDs.contains(request.id) == false else {
            return .cancelled(requestID: request.id)
        }
        guard let handler = handlers[request.address] else {
            return .failed(
                requestID: request.id,
                code: "ROUTE_NOT_FOUND",
                message: "No workspace bus route is registered for \(request.address)."
            )
        }

        let context = WorkspaceHandlerContext(
            bus: self,
            workspaceRoot: workspaceRoot,
            settings: loadSettings(namespace: request.address.namespace)
        )
        let response = await run(handler: handler, request: request, context: context, timeout: timeout)
        if cancelledRequestIDs.contains(request.id), response.status == .ok {
            return .cancelled(requestID: request.id)
        }
        return response
    }

    func cancel(requestID: UUID) async {
        cancelledRequestIDs.insert(requestID)
        await publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: requestID,
            address: WorkspaceMessageAddress(namespace: "workspace.bus", capability: "cancel"),
            origin: nil,
            kind: .diagnostic,
            payload: .jsonString(#"{"code":"REQUEST_CANCELLED"}"#)
        ))
    }

    func subscribe(_ filter: WorkspaceMessageEventFilter) -> AsyncStream<WorkspaceMessageEvent> {
        let subscriberID = UUID()
        return AsyncStream { continuation in
            subscribers[subscriberID] = Subscriber(filter: filter, continuation: continuation)
            for event in eventBuffer where filter.matches(event) {
                continuation.yield(event)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id: subscriberID) }
            }
        }
    }

    func publish(_ event: WorkspaceMessageEvent) async {
        eventBuffer.append(event)
        trimEventBuffer()
        for subscriber in subscribers.values where subscriber.filter.matches(event) {
            subscriber.continuation.yield(event)
        }
    }

    private func run(
        handler: any WorkspaceMessageHandler,
        request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        timeout: Duration?
    ) async -> WorkspaceMessageResponse {
        guard let timeout else {
            return await handler.handle(request, context: context)
        }

        return await withTaskGroup(of: WorkspaceMessageResponse.self) { group in
            group.addTask {
                await handler.handle(request, context: context)
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return .cancelled(requestID: request.id)
                }
                return .timedOut(requestID: request.id)
            }

            let first = await group.next() ?? .failed(
                requestID: request.id,
                code: "REQUEST_FAILED",
                message: "Workspace message request produced no response."
            )
            group.cancelAll()
            return first
        }
    }

    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func loadSettings(namespace: String) -> WorkspaceSettingsNamespace {
        guard let settingsRootURL else {
            return WorkspaceSettingsNamespace(namespace: namespace, values: [:])
        }
        let url = settingsRootURL.appendingPathComponent("\(namespace).toml")
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return WorkspaceSettingsNamespace(namespace: namespace, values: [:])
        }
        var values: [String: WorkspaceSettingsValue] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.isEmpty == false,
                  line.hasPrefix("#") == false,
                  let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[String(key)] = parseSettingsValue(String(value))
        }
        return WorkspaceSettingsNamespace(namespace: namespace, values: values)
    }

    private func parseSettingsValue(_ value: String) -> WorkspaceSettingsValue {
        if value == "true" { return .boolean(true) }
        if value == "false" { return .boolean(false) }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            var text = value
            text.removeFirst()
            text.removeLast()
            return .string(text.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
        }
        if let integer = Int(value) { return .integer(integer) }
        if let double = Double(value) { return .double(double) }
        return .string(value)
    }

    private func trimEventBuffer() {
        guard eventBuffer.count > eventCapacity else { return }
        eventBuffer.removeFirst(eventBuffer.count - eventCapacity)
    }
}

final class ClosureWorkspaceMessageHandler: WorkspaceMessageHandler, @unchecked Sendable {
    private let requiredScope: WorkspacePermissionScope
    private let handler: (String) async throws -> String

    init(
        requiredScope: WorkspacePermissionScope,
        handler: @escaping (String) async throws -> String
    ) {
        self.requiredScope = requiredScope
        self.handler = handler
    }

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(requiredScope) else {
            return .unauthorized(requestID: request.id, message: "scope")
        }
        do {
            let output = try await handler(request.payload.stringValue())
            return .ok(requestID: request.id, payload: .jsonString(output))
        } catch {
            return .failed(requestID: request.id, code: "HANDLER_ERROR", message: String(describing: error))
        }
    }
}
