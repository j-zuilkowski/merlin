import XCTest
@testable import Merlin

final class DomainCapabilityBusTests: XCTestCase {
    func testBuiltInDomainsExposeBusCapabilities() {
        let software = SoftwareDomain()
        let electronics = ElectronicsDomain()

        XCTAssertTrue(software.capabilities.contains { $0.kind == .verification })
        XCTAssertTrue(electronics.capabilities.contains { $0.address.namespace == "domain.electronics" })
        XCTAssertNotNil(electronics.settingsSchema)
    }

    func testMCPDomainAdapterConvertsManifestToCapabilities() async {
        let manifest = DomainManifest(
            id: "kicad",
            displayName: "KiCad",
            taskTypes: [],
            highStakesKeywords: [],
            systemPromptAddendum: nil,
            mcpToolNames: ["mcp:kicad:kicad_run_drc"],
            verificationCommands: [:]
        )
        let adapter = await MainActor.run {
            MCPDomainAdapter(manifest: manifest, mcpServerID: "kicad", mcpToolNames: ["mcp:kicad:kicad_run_drc"])
        }

        XCTAssertEqual(adapter.canonicalDomainID, ElectronicsDomain.defaultID)
        XCTAssertTrue(adapter.capabilities.contains { $0.kind == .tool })
    }
}
