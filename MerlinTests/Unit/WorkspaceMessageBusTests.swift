import XCTest
@testable import Merlin

final class WorkspaceMessageBusTests: XCTestCase {
    func testRegisteredHandlerReceivesRequestAndReturnsPayload() async throws {
        let address = WorkspaceMessageAddress(namespace: "test", capability: "echo")
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        await bus.register(EchoWorkspaceHandler(requiredScope: .readOnly), for: address)

        let response = await bus.send(request(address: address, scope: .readOnly, payload: #"{"message":"ok"}"#))

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.payload?.stringValue(), #"{"message":"ok"}"#)
    }

    func testMissingRouteReturnsRouteNotFound() async {
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let response = await bus.send(request(
            address: WorkspaceMessageAddress(namespace: "missing", capability: "tool"),
            scope: .readOnly
        ))

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.diagnostics.first?.code, "ROUTE_NOT_FOUND")
    }

    func testInsufficientScopeReturnsUnauthorized() async {
        let address = WorkspaceMessageAddress(namespace: "test", capability: "write")
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        await bus.register(EchoWorkspaceHandler(requiredScope: .workspaceWrite), for: address)

        let response = await bus.send(request(address: address, scope: .readOnly))

        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(response.diagnostics.first?.code, "UNAUTHORIZED_SCOPE")
    }

    func testTimeoutReturnsTimedOutDiagnostic() async {
        let address = WorkspaceMessageAddress(namespace: "test", capability: "slow")
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        await bus.register(SlowWorkspaceHandler(), for: address)

        let response = await bus.send(
            request(address: address, scope: .readOnly),
            timeout: .milliseconds(10)
        )

        XCTAssertEqual(response.status, .timedOut)
        XCTAssertEqual(response.diagnostics.first?.code, "REQUEST_TIMED_OUT")
    }

    func testTimeoutReturnsWithoutWaitingForBlockingHandlerToFinish() async {
        let address = WorkspaceMessageAddress(namespace: "test", capability: "blocked")
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        await bus.register(BlockingWorkspaceHandler(), for: address)

        let start = Date()
        let response = await bus.send(
            request(address: address, scope: .readOnly),
            timeout: .milliseconds(10)
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(response.status, .timedOut)
        XCTAssertLessThan(elapsed, 0.5)
    }

    func testCancelPublishesCancellationEvent() async {
        let bus = WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let requestID = UUID()
        await bus.cancel(requestID: requestID)

        let events = await bus.recentEvents(matching: WorkspaceMessageEventFilter(requestID: requestID))
        XCTAssertEqual(events.first?.kind, .diagnostic)
        XCTAssertEqual(events.first?.requestID, requestID)
    }

    func testSubscribersReceiveMatchingEventsAndRingBufferIsBounded() async {
        let bus = WorkspaceMessageBus(
            workspaceID: "workspace",
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            eventCapacity: 100
        )
        let address = WorkspaceMessageAddress(namespace: "test.events", capability: "progress")
        let stream = await bus.subscribe(WorkspaceMessageEventFilter(namespacePrefix: "test."))

        await bus.publish(event(kind: .progress, address: address, index: 0))
        await bus.publish(event(kind: .artifactProduced, address: address, index: 1))
        await bus.publish(event(kind: .healthChanged, address: address, index: 2))
        await bus.publish(event(kind: .diagnostic, address: address, index: 3))
        await bus.publish(event(kind: .approvalRequired, address: address, index: 4))
        await bus.publish(event(kind: .settingsChanged, address: address, index: 5))
        await bus.publish(event(kind: .settingsValidation, address: address, index: 6))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.kind, .progress)

        for index in 7..<130 {
            await bus.publish(event(kind: .progress, address: address, index: index))
        }

        let recent = await bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "test."))
        XCTAssertEqual(recent.count, 100)
        XCTAssertEqual(recent.last?.kind, .progress)
    }

    private func request(
        address: WorkspaceMessageAddress,
        scope: WorkspacePermissionScope,
        payload: String = "{}"
    ) -> WorkspaceMessageRequest {
        WorkspaceMessageRequest(
            id: UUID(),
            address: address,
            origin: WorkspaceMessageOrigin(
                workspaceID: "workspace",
                sessionID: nil,
                agentID: nil,
                subagentID: nil,
                worktreeID: nil,
                subagentDepth: 0,
                permissionScope: scope,
                activeDomainIDs: ["software"]
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        )
    }

    private func event(
        kind: WorkspaceMessageEventKind,
        address: WorkspaceMessageAddress,
        index: Int
    ) -> WorkspaceMessageEvent {
        WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: address,
            origin: nil,
            kind: kind,
            payload: .jsonString(#"{"index":\#(index)}"#)
        )
    }
}

private struct EchoWorkspaceHandler: WorkspaceMessageHandler {
    var requiredScope: WorkspacePermissionScope

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(requiredScope) else {
            return .unauthorized(requestID: request.id, message: "scope")
        }
        return .ok(requestID: request.id, payload: request.payload)
    }
}

private struct SlowWorkspaceHandler: WorkspaceMessageHandler {
    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        try? await Task.sleep(for: .seconds(5))
        return .ok(requestID: request.id, payload: .jsonString("{}"))
    }
}

private struct BlockingWorkspaceHandler: WorkspaceMessageHandler {
    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        Thread.sleep(forTimeInterval: 2)
        return .ok(requestID: request.id, payload: .jsonString("{}"))
    }
}
