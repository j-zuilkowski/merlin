import XCTest
@testable import Merlin

final class DocReferenceGraphTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drg-\(UUID())")
        let srcDir = dir.appendingPathComponent("Src")
        let docDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - build produces reference when doc mentions source symbol

    func testBuildProducesReferenceForKnownSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        struct ProviderBudget: Sendable {
            let maxInputTokens: Int
        }
        """.write(to: proj.appendingPathComponent("Src/ProviderBudget.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # Architecture

        `ProviderBudget` controls how many tokens each provider can receive.
        """.write(to: proj.appendingPathComponent("docs/architecture.md"),
                  atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: proj.path)
        let match = refs.first { $0.codeSymbol == "ProviderBudget" }
        XCTAssertNotNil(match, "Expected reference for ProviderBudget")
        XCTAssertTrue(match?.docFile.hasSuffix("architecture.md") == true)
    }

    // MARK: - build does not produce reference for unknown symbol

    func testBuildNoReferenceForUnknownSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        # Architecture

        `NonExistentSymbol` is mentioned here but does not exist in source.
        """.write(to: proj.appendingPathComponent("docs/architecture.md"),
                  atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: proj.path)
        let match = refs.first { $0.codeSymbol == "NonExistentSymbol" }
        XCTAssertNil(match, "Should not produce reference for unknown symbol")
    }

    // MARK: - staleReferences

    func testStaleReferencesMatchesChangedSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try "struct ProviderBudget {}".write(
            to: proj.appendingPathComponent("Src/PB.swift"),
            atomically: true, encoding: .utf8)
        try "# Doc\n\n`ProviderBudget` is used here.".write(
            to: proj.appendingPathComponent("docs/guide.md"),
            atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        _ = await graph.build(projectPath: proj.path)
        let stale = await graph.staleReferences(against: ["ProviderBudget"])
        XCTAssertFalse(stale.isEmpty, "ProviderBudget should appear as stale")
    }

    func testStaleReferencesIgnoresUnrelatedSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try "struct ProviderBudget {}".write(
            to: proj.appendingPathComponent("Src/PB.swift"),
            atomically: true, encoding: .utf8)
        try "# Doc\n\n`ProviderBudget` is here.".write(
            to: proj.appendingPathComponent("docs/guide.md"),
            atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        _ = await graph.build(projectPath: proj.path)
        let stale = await graph.staleReferences(against: ["SomeOtherThing"])
        XCTAssertTrue(stale.isEmpty, "No stale refs for unrelated symbol")
    }
}
