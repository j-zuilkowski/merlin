import XCTest
@testable import Merlin

@MainActor
final class MultiDomainRegistryTests: XCTestCase {

    func test_registryActivatesMultipleDomainsInStableOrder() async {
        let registry = DomainRegistry()
        await registry.register(StubDomain(id: "pcb", displayName: "PCB", taskTypes: [
            DomainTaskType(domainID: "pcb", name: "schematic", displayName: "Schematic")
        ]))
        await registry.register(StubDomain(id: "docs", displayName: "Docs", taskTypes: [
            DomainTaskType(domainID: "docs", name: "writing", displayName: "Writing")
        ]))

        await registry.setActiveDomains(ids: ["docs", "pcb"])

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software", "docs", "pcb"])
    }

    func test_taskTypesMergesAllActiveDomains() async {
        let registry = DomainRegistry()
        await registry.register(StubDomain(id: "pcb", displayName: "PCB", taskTypes: [
            DomainTaskType(domainID: "pcb", name: "schematic", displayName: "Schematic")
        ]))
        await registry.register(StubDomain(id: "docs", displayName: "Docs", taskTypes: [
            DomainTaskType(domainID: "docs", name: "writing", displayName: "Writing")
        ]))

        await registry.setActiveDomains(ids: ["pcb", "docs"])

        let taskTypes = await registry.taskTypes()
        let names = Set(taskTypes.map(\.name))
        XCTAssertTrue(names.contains("code_generation"))
        XCTAssertTrue(names.contains("schematic"))
        XCTAssertTrue(names.contains("writing"))
    }

    func test_unregisteredDomainIDsDoNotDropSoftware() async {
        let registry = DomainRegistry()
        await registry.register(StubDomain(id: "pcb", displayName: "PCB"))

        await registry.setActiveDomains(ids: ["ghost"])

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software"])
    }

    func test_unregisteringActiveDomainRemovesOnlyThatDomain() async {
        let registry = DomainRegistry()
        await registry.register(StubDomain(id: "pcb", displayName: "PCB"))
        await registry.register(StubDomain(id: "docs", displayName: "Docs"))
        await registry.setActiveDomains(ids: ["pcb", "docs"])

        await registry.unregister(id: "pcb")

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software", "docs"])
    }

    func test_softwareRemainsFallbackWhenActiveListInvalid() async {
        let registry = DomainRegistry()
        await registry.setActiveDomains(ids: ["ghost", "missing"])

        let active = await registry.activeDomains().map(\.id)
        XCTAssertEqual(active, ["software"])
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
