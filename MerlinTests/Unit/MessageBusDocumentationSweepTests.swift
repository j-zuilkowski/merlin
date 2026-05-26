import XCTest

final class MessageBusDocumentationSweepTests: XCTestCase {
    func testDeveloperManualDocumentsBusSurfaces() throws {
        let manual = try read("Merlin/Docs/DeveloperManual.md")
        for required in [
            "WorkspaceRuntime",
            "WorkspaceMessageBus",
            "WorkspaceMessageOrigin",
            "tool handler groups",
            "MCP bus transport",
            "domain capability routing",
            "verification routing",
            "settings schemas",
            "event/artifact flow",
        ] {
            XCTAssertTrue(manual.contains(required), "Missing Developer Manual coverage for \(required)")
        }
    }

    func testReleaseCurrentDocsDoNotMarkMessageBusPlanned() throws {
        for path in ["spec.md", "vision.md", "FEATURES.md", "Merlin/Docs/UserGuide.md", "Merlin/Docs/DeveloperManual.md"] {
            let text = try read(path)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("WorkspaceMessageBus planned"), path)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("message bus is planned"), path)
            XCTAssertFalse(text.contains("direct ToolRouter closure dispatch"), path)
        }
    }

    private func read(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
