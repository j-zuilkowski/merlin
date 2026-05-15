import XCTest
@testable import Merlin

final class DocReferenceSectionTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testReferencesCarryTheSectionTheyAppearUnder() async throws {
        try writeFile("Sources/Symbols.swift", """
        struct EngineCore {}
        struct StorageLayer {}
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ## Engine

        The `EngineCore` type runs the loop.

        ## Storage

        The `StorageLayer` type persists state.
        """)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: projectRoot.path)

        let engineRef = refs.first { $0.codeSymbol == "EngineCore" }
        let storageRef = refs.first { $0.codeSymbol == "StorageLayer" }

        XCTAssertEqual(engineRef?.docSection, "Engine",
                       "EngineCore is mentioned under the 'Engine' heading")
        XCTAssertEqual(storageRef?.docSection, "Storage",
                       "StorageLayer is mentioned under the 'Storage' heading")
    }
}
