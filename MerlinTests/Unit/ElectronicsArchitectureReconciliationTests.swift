import XCTest
@testable import Merlin

final class ElectronicsArchitectureReconciliationTests: XCTestCase {
    func testActiveArchitectureDocsDoNotDescribeMerlinKiCadMCPAsCurrent() throws {
        let checked = [
            "spec.md",
            "vision.md",
            "FEATURES.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
        ]

        for path in checked {
            let text = try repoText(path)
            XCTAssertFalse(text.contains("target server is `merlin-kicad-mcp`"), path)
            XCTAssertFalse(text.contains("Merlin v2.0 owns the KiCad MCP integration layer"), path)
            XCTAssertFalse(text.contains("Routing uses FreeRouting first, wrapped by `merlin-kicad-mcp`"), path)
            XCTAssertFalse(text.contains("delegated to `merlin-kicad-mcp`"), path)
        }
    }

    func testActiveArchitectureDocsNameBusBackedElectronicsPlugin() throws {
        let joined = try [
            "spec.md",
            "vision.md",
            "FEATURES.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
        ].map { try repoText($0) }.joined(separator: "\n")

        XCTAssertTrue(joined.contains("plugins/electronics"))
        XCTAssertTrue(joined.contains("workspace message bus"))
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("historical reference"))
    }
}
