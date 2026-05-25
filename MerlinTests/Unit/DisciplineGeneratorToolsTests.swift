import XCTest
@testable import Merlin

/// Task 300a - failing tests for discipline generator tools.
@MainActor
final class DisciplineGeneratorToolsTests: XCTestCase {

    func testDisciplineGeneratorToolsAreRegistered() {
        ToolRegistry.shared.registerBuiltins()
        let expected = ["generate_api_docs", "generate_dev_guide",
                        "write_vale_styles", "scaffold_manual_coverage"]
        for name in expected {
            XCTAssertTrue(ToolRegistry.shared.contains(named: name),
                          "discipline tool '\(name)' must be registered")
        }
    }
}
