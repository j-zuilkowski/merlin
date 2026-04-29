import XCTest
@testable import Merlin

final class DomainRegistryTests: XCTestCase {

    // Each test gets an isolated registry to avoid cross-test state.
    // DomainRegistry.shared is the singleton used at runtime; tests
    // use a fresh local instance via a dedicated init.

    func testActiveDomainDefaultsToSoftwareDomain() async {
        let registry = DomainRegistry()
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testRegisterAndActivateDomain() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        await registry.setActiveDomain(id: "pcb")
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "pcb")
    }

    func testUnregisterDomainFallsBackToSoftware() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        await registry.setActiveDomain(id: "pcb")
        await registry.unregister(id: "pcb")
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testSoftwareDomainCannotBeUnregistered() async {
        let registry = DomainRegistry()
        await registry.unregister(id: "software")  // should be a no-op
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testTaskTypesReturnsActiveDomainOnlyNotUnion() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design",
                             taskTypes: [DomainTaskType(domainID: "pcb", name: "schematic", displayName: "Schematic")])
        await registry.register(pcb)

        // While software is active, only software task types returned
        let softwareTypes = await registry.taskTypes()
        XCTAssertTrue(softwareTypes.allSatisfy { $0.domainID == "software" })

        await registry.setActiveDomain(id: "pcb")
        let pcbTypes = await registry.taskTypes()
        XCTAssertTrue(pcbTypes.allSatisfy { $0.domainID == "pcb" })
        XCTAssertFalse(pcbTypes.contains(where: { $0.domainID == "software" }))
    }

    func testPluginLookup() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        let found = await registry.plugin(for: "pcb")
        XCTAssertEqual(found?.id, "pcb")
        let missing = await registry.plugin(for: "nonexistent")
        XCTAssertNil(missing)
    }
}

final class DomainManifestTests: XCTestCase {

    func testDecodesManifestFromJSON() throws {
        let json = """
        {
            "id": "pcb",
            "displayName": "PCB Design",
            "taskTypes": [
                { "domainID": "pcb", "name": "schematic", "displayName": "Schematic Design" }
            ],
            "highStakesKeywords": ["power routing", "impedance"],
            "systemPromptAddendum": "Always follow IPC-2221 spacing rules.",
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        XCTAssertEqual(manifest.id, "pcb")
        XCTAssertEqual(manifest.taskTypes.count, 1)
        XCTAssertEqual(manifest.taskTypes[0].name, "schematic")
        XCTAssertEqual(manifest.highStakesKeywords, ["power routing", "impedance"])
        XCTAssertEqual(manifest.systemPromptAddendum, "Always follow IPC-2221 spacing rules.")
    }

    func testMCPDomainAdapterAdoptsDomainPlugin() throws {
        let json = """
        {
            "id": "pcb",
            "displayName": "PCB Design",
            "taskTypes": [],
            "highStakesKeywords": [],
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        let adapter = MCPDomainAdapter(manifest: manifest, mcpServerID: "pcb-server")
        XCTAssertEqual(adapter.id, "pcb")
        XCTAssertEqual(adapter.displayName, "PCB Design")
        XCTAssertNil(adapter.systemPromptAddendum)
    }
}

// MARK: - Test helpers

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
