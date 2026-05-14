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

    func test_restoreKeepsSessionDomainsIndependentOfSharedRegistry() async {
        let registry = DomainRegistry.shared
        await registry.register(StubDomain(id: "pcb", displayName: "PCB", systemPromptAddendum: "[PCB]"))
        await registry.register(StubDomain(id: "docs", displayName: "Docs", systemPromptAddendum: "[DOCS]"))
        await registry.setActiveDomains(ids: ["software"])

        let ref = ProjectRef(path: "/tmp/multi-domain-\(UUID().uuidString)", displayName: "test")
        let manager = SessionManager(projectRef: ref)
        let software = await manager.newSession()
        let session = Session(
            title: "Restored",
            messages: [],
            activeDomainIDs: ["pcb"]
        )

        let restored = await manager.restore(session: session)
        manager.switchSession(to: software.id)
        manager.switchSession(to: restored.id)

        XCTAssertEqual(software.activeDomainIDs, ["software"])
        XCTAssertEqual(software.appState.engine.activeDomainIDs, ["software"])
        XCTAssertEqual(restored.activeDomainIDs, ["software", "pcb"])
        XCTAssertEqual(restored.appState.engine.activeDomainIDs, ["software", "pcb"])

        let softwarePrompt = await software.appState.engine.buildSystemPromptForTesting(slot: .execute)
        let restoredPrompt = await restored.appState.engine.buildSystemPromptForTesting(slot: .execute)

        XCTAssertFalse(softwarePrompt.contains("[PCB]"))
        XCTAssertTrue(restoredPrompt.contains("[PCB]"))

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software"])

        await registry.unregister(id: "pcb")
        await registry.unregister(id: "docs")
        await registry.setActiveDomains(ids: ["software"])
    }
}

private struct StubDomain: DomainPlugin {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType]
    var verificationBackend: any VerificationBackend = NullVerificationBackend()
    var highStakesKeywords: [String] = []
    var systemPromptAddendum: String? = nil
    var mcpToolNames: [String] = []

    init(id: String,
         displayName: String,
         taskTypes: [DomainTaskType] = [DomainTaskType(domainID: "stub", name: "task", displayName: "Task")],
         systemPromptAddendum: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.taskTypes = taskTypes
        self.systemPromptAddendum = systemPromptAddendum
    }
}
