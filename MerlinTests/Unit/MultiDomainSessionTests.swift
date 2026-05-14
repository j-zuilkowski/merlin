import XCTest
@testable import Merlin

@MainActor
final class MultiDomainSessionTests: XCTestCase {

    func test_sessionEncodesAndDecodesActiveDomainIDs() throws {
        let session = Session(
            title: "Test",
            messages: [],
            activeDomainIDs: ["software", "pcb"]
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        XCTAssertEqual(decoded.activeDomainIDs, ["software", "pcb"])
    }

    func test_olderSessionJSONDefaultsToSoftwareDomain() throws {
        let json = """
        {
          "title": "Legacy",
          "messages": []
        }
        """
        let decoded = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.activeDomainIDs, ["software"])
    }

    func test_restoreAppliesRestoredDomainsToSharedRegistry() async {
        let registry = DomainRegistry.shared
        await registry.register(StubDomain(id: "pcb", displayName: "PCB"))
        await registry.setActiveDomains(ids: ["software"])

        let ref = ProjectRef(path: "/tmp/multi-domain-\(UUID().uuidString)", displayName: "test")
        let manager = SessionManager(projectRef: ref)
        let session = Session(
            title: "Restored",
            messages: [],
            activeDomainIDs: ["pcb"]
        )

        _ = await manager.restore(session: session)

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software", "pcb"])
    }
}

private struct StubDomain: DomainPlugin {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType] = [
        DomainTaskType(domainID: "stub", name: "task", displayName: "Task")
    ]
    var verificationBackend: any VerificationBackend = NullVerificationBackend()
    var highStakesKeywords: [String] = []
    var systemPromptAddendum: String? = nil
    var mcpToolNames: [String] = []
}
