import XCTest
@testable import Merlin

final class WorkspaceMessageContractTests: XCTestCase {
    func testAddressIsCodableHashableAndReadable() throws {
        let address = WorkspaceMessageAddress(namespace: "builtin.files", capability: "read_file")
        XCTAssertEqual(address.description, "builtin.files/read_file")
        XCTAssertEqual(Set([address]).first, address)

        let data = try JSONEncoder().encode(address)
        let decoded = try JSONDecoder().decode(WorkspaceMessageAddress.self, from: data)
        XCTAssertEqual(decoded, address)
    }

    func testPayloadStoresCanonicalJSONAndDecodesCodableValues() throws {
        struct Payload: Codable, Equatable {
            var path: String
            var recursive: Bool
        }

        let payload = try WorkspaceMessagePayload.encodeJSON(Payload(path: "/tmp/project", recursive: true))
        XCTAssertEqual(payload.contentType, "application/json")
        XCTAssertEqual(try payload.decodeJSON(Payload.self), Payload(path: "/tmp/project", recursive: true))
        XCTAssertFalse(payload.stringValue().contains("PNG:"))
    }

    func testOriginCarriesWorkspaceSessionSubagentWorktreeAndDomains() {
        let sessionID = UUID()
        let subagentID = UUID()
        let origin = WorkspaceMessageOrigin(
            workspaceID: "workspace-1",
            sessionID: sessionID,
            agentID: UUID(),
            subagentID: subagentID,
            worktreeID: "worker-tree",
            subagentDepth: 1,
            permissionScope: .worktreeWrite,
            activeDomainIDs: ["software", "electronics"]
        )

        XCTAssertEqual(origin.workspaceID, "workspace-1")
        XCTAssertEqual(origin.sessionID, sessionID)
        XCTAssertEqual(origin.subagentID, subagentID)
        XCTAssertEqual(origin.worktreeID, "worker-tree")
        XCTAssertEqual(origin.subagentDepth, 1)
        XCTAssertEqual(origin.permissionScope, .worktreeWrite)
        XCTAssertEqual(origin.activeDomainIDs, ["software", "electronics"])
    }

    func testPermissionScopeEscalationRules() {
        XCTAssertTrue(WorkspacePermissionScope.readOnly.allows(.readOnly))
        XCTAssertFalse(WorkspacePermissionScope.readOnly.allows(.workspaceWrite))
        XCTAssertFalse(WorkspacePermissionScope.readOnly.allows(.externalSideEffect))

        XCTAssertTrue(WorkspacePermissionScope.worktreeWrite.allows(.readOnly))
        XCTAssertTrue(WorkspacePermissionScope.worktreeWrite.allows(.worktreeWrite))
        XCTAssertFalse(WorkspacePermissionScope.worktreeWrite.allows(.workspaceWrite))

        XCTAssertTrue(WorkspacePermissionScope.workspaceWrite.allows(.readOnly))
        XCTAssertTrue(WorkspacePermissionScope.workspaceWrite.allows(.worktreeWrite))
        XCTAssertTrue(WorkspacePermissionScope.workspaceWrite.allows(.workspaceWrite))
        XCTAssertFalse(WorkspacePermissionScope.workspaceWrite.allows(.userApprovedIrreversible))

        XCTAssertTrue(WorkspacePermissionScope.externalSideEffect.allows(.readOnly))
        XCTAssertTrue(WorkspacePermissionScope.externalSideEffect.allows(.externalSideEffect))
        XCTAssertFalse(WorkspacePermissionScope.externalSideEffect.allows(.workspaceWrite))

        for scope in WorkspacePermissionScope.allCases {
            XCTAssertTrue(WorkspacePermissionScope.userApprovedIrreversible.allows(scope))
        }
    }

    func testStandardDiagnosticsUseStableCodes() {
        let requestID = UUID()
        let missingRoute = WorkspaceMessageResponse.failed(
            requestID: requestID,
            code: "ROUTE_NOT_FOUND",
            message: "missing"
        )
        XCTAssertEqual(missingRoute.status, .failed)
        XCTAssertEqual(missingRoute.diagnostics.first?.code, "ROUTE_NOT_FOUND")

        let unauthorized = WorkspaceMessageResponse.unauthorized(
            requestID: requestID,
            message: "scope"
        )
        XCTAssertEqual(unauthorized.status, .unauthorized)
        XCTAssertEqual(unauthorized.diagnostics.first?.code, "UNAUTHORIZED_SCOPE")
    }
}
