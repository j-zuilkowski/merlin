import XCTest
@testable import Merlin

final class VerificationBusTests: XCTestCase {
    func testVerificationMessageHandlerRunsBackendCommands() async {
        let backend = StaticVerificationBackend(commands: [
            VerificationCommand(label: "pass", command: "true", passCondition: .exitCode(0))
        ])
        let handler = VerificationMessageHandler(backend: backend)
        let request = WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "domain.software", capability: "verify"),
            origin: WorkspaceMessageOrigin.parentSession(workspaceID: "workspace", sessionID: nil, activeDomainIDs: ["software"]),
            payload: .jsonString(#"{"domain_id":"software","task_type":"test"}"#),
            cancellationGroup: nil
        )

        let response = await handler.handle(request, context: WorkspaceHandlerContext(
            bus: WorkspaceMessageBus(workspaceID: "workspace", workspaceRoot: URL(fileURLWithPath: "/tmp")),
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            settings: WorkspaceSettingsNamespace(namespace: "domain.software", values: [:])
        ))

        XCTAssertEqual(response.status, .ok)
    }
}

private struct StaticVerificationBackend: VerificationBackend {
    var commands: [VerificationCommand]

    func verificationCommands(for taskType: DomainTaskType) async -> [VerificationCommand]? {
        commands
    }
}
