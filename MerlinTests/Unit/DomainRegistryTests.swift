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

    func testElectronicsDomainIsRegisteredByDefault() async {
        let registry = DomainRegistry()
        let electronics = await registry.plugin(for: ElectronicsDomain.defaultID)
        XCTAssertEqual(electronics?.displayName, "Electronics")
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

    func testTaskTypesReturnsMergedActiveDomains() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design",
                             taskTypes: [DomainTaskType(domainID: "pcb", name: "schematic", displayName: "Schematic")])
        await registry.register(pcb)

        // While software is active, software task types are returned.
        let softwareTypes = await registry.taskTypes()
        XCTAssertTrue(softwareTypes.allSatisfy { $0.domainID == "software" })

        await registry.setActiveDomain(id: "pcb")
        let pcbTypes = await registry.taskTypes()
        XCTAssertTrue(pcbTypes.contains(where: { $0.domainID == "software" }))
        XCTAssertTrue(pcbTypes.contains(where: { $0.domainID == "pcb" }))
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

    func testScopedDomainsIncludeExternalAdapterForCanonicalElectronics() async throws {
        let registry = DomainRegistry()
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: Data("""
        {
            "id": "kicad",
            "displayName": "KiCad MCP",
            "taskTypes": [],
            "highStakesKeywords": [],
            "mcpToolNames": ["route_board"],
            "verificationCommands": {}
        }
        """.utf8))
        let adapter = await MainActor.run {
            MCPDomainAdapter(manifest: manifest, mcpServerID: "kicad", mcpToolNames: ["mcp:kicad:route_board"])
        }

        await registry.register(adapter)

        let scoped = await registry.scopedDomains(ids: ["electronics"]).map(\.id)
        XCTAssertTrue(scoped.contains(ElectronicsDomain.defaultID))
        XCTAssertTrue(scoped.contains(adapter.id))

        let available = await registry.availableDomains().map(\.id)
        XCTAssertFalse(available.contains(adapter.id))
    }

    func testElectronicsActivationSuggestionTriggersForKiCadPrompt() {
        let suggestion = ElectronicsDomain.suggestedActivation(
            for: "Please route this KiCad PCB and export Gerbers.",
            currentActiveDomainIDs: SoftwareDomain.defaultActiveDomainIDs
        )

        XCTAssertEqual(suggestion?.domainID, ElectronicsDomain.defaultID)
        XCTAssertEqual(suggestion?.displayName, "Electronics")
    }

    func testElectronicsActivationSuggestionTriggersForBoardDesignIntent() {
        let suggestion = ElectronicsDomain.suggestedActivation(
            for: "Design a board layout for this sensor breakout and place the components.",
            currentActiveDomainIDs: SoftwareDomain.defaultActiveDomainIDs
        )

        XCTAssertEqual(suggestion?.domainID, ElectronicsDomain.defaultID)
    }

    func testElectronicsActivationSuggestionDoesNotTriggerForNormalSoftwarePrompt() {
        let suggestion = ElectronicsDomain.suggestedActivation(
            for: "Design a dashboard layout for the settings screen and route the button actions.",
            currentActiveDomainIDs: SoftwareDomain.defaultActiveDomainIDs
        )

        XCTAssertNil(suggestion)
    }

    func testElectronicsActivationSuggestionDoesNotTriggerWhenAlreadyActive() {
        let suggestion = ElectronicsDomain.suggestedActivation(
            for: "Open the schematic and update the footprint assignments.",
            currentActiveDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        )

        XCTAssertNil(suggestion)
    }
}

@MainActor
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
            "mcpToolNames": ["route_board"],
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        XCTAssertEqual(manifest.id, "pcb")
        XCTAssertEqual(manifest.taskTypes.count, 1)
        XCTAssertEqual(manifest.taskTypes[0].name, "schematic")
        XCTAssertEqual(manifest.highStakesKeywords, ["power routing", "impedance"])
        XCTAssertEqual(manifest.systemPromptAddendum, "Always follow IPC-2221 spacing rules.")
        XCTAssertEqual(manifest.mcpToolNames, ["route_board"])
    }

    func testMCPDomainAdapterAdoptsDomainPlugin() throws {
        let json = """
        {
            "id": "pcb",
            "displayName": "PCB Design",
            "taskTypes": [],
            "highStakesKeywords": [],
            "mcpToolNames": ["route_board"],
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        let adapter = MCPDomainAdapter(
            manifest: manifest,
            mcpServerID: "pcb-server",
            mcpToolNames: ["mcp:pcb-server:route_board"]
        )
        XCTAssertEqual(adapter.id, "mcp:pcb-server:pcb")
        XCTAssertEqual(adapter.canonicalDomainID, ElectronicsDomain.defaultID)
        XCTAssertEqual(adapter.displayName, "PCB Design")
        XCTAssertNil(adapter.systemPromptAddendum)
        XCTAssertEqual(adapter.mcpToolNames, ["mcp:pcb-server:route_board"])
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
