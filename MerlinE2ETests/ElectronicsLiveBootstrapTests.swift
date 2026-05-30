import XCTest
@testable import Merlin

@MainActor
final class ElectronicsLiveBootstrapTests: XCTestCase {
    func testElectronicsLiveSessionOffersFirstPartyKiCadToolsAndGatesImprovisation() async throws {
        try skipUnlessLiveEnvironment()
        try XCTSkipUnless(EvalPaths.fixtureExists("electronics"),
                          "electronics fixture missing")

        let session = LiveSession(
            projectRef: ProjectRef(
                path: EvalPaths.fixture("electronics"),
                displayName: "electronics",
                lastOpenedAt: Date()
            ),
            activeDomainIDs: [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        )
        defer {
            Task { @MainActor in
                await session.close()
            }
        }

        await session.awaitMCPReady()

        let offered = Set(session.appState.engine.offeredToolNamesForTesting())
        XCTAssertTrue(offered.contains("kicad_route_pass"))
        XCTAssertTrue(offered.contains("kicad_run_erc"))
        XCTAssertFalse(offered.contains("bash"))
        XCTAssertFalse(offered.contains("run_shell"))
        XCTAssertFalse(offered.contains("write_file"))
        XCTAssertFalse(offered.contains("create_file"))
        XCTAssertFalse(offered.contains("spawn_agent"))
    }
}
