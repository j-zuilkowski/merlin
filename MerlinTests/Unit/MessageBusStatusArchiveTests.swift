import XCTest

final class MessageBusStatusArchiveTests: XCTestCase {
    private var repoRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("project.yml").path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testVisionMarksMessageBusFoundationImplemented() throws {
        let text = try read("vision.md")

        XCTAssertTrue(text.contains("message bus foundation is implemented"))
        XCTAssertFalse(text.contains("Implementation must start with `WorkspaceRuntime`"))
        XCTAssertFalse(text.contains("scaffold must be reworked into `electronics/` per the above during that implementation"))
    }

    func testSpecPresentsMessageBusSequenceAsCompletedStatus() throws {
        let text = try read("spec.md")

        XCTAssertTrue(text.contains("### Completed Message Bus Implementation Sequence"))
        XCTAssertFalse(text.contains("The bus architecture must be implemented in this order:"))
        XCTAssertFalse(text.contains("This is the required foundation before the runtime plugin loader and before moving electronics into `plugins/electronics/`."))
    }

    func testLegacyKiCadMCPScaffoldIsArchivedNotActive() {
        let active = repoRoot.appendingPathComponent("plugins/merlin-kicad-mcp")
        let archive = repoRoot.appendingPathComponent("archive/legacy-merlin-kicad-mcp")

        XCTAssertFalse(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("Package.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("README.md").path))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
