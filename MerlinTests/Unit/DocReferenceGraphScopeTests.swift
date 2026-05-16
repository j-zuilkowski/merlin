import XCTest
@testable import Merlin

/// Phase 316a — failing tests for DocReferenceGraph scoping.
final class DocReferenceGraphScopeTests: XCTestCase {

    func testPhasesDocsAndTestSymbolsAreNotFlagged() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-scope-\(UUID())", isDirectory: true)
        let phasesDir = dir.appendingPathComponent("phases")
        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(
            at: phasesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A test-target source file declaring a symbol.
        try "final class WidgetSpecHelper {}\n".write(
            to: testsDir.appendingPathComponent("WidgetSpecHelper.swift"),
            atomically: true, encoding: .utf8)
        // A phase doc citing an identifier that exists nowhere in the tree.
        try "# Phase 1\nUses `BogusPhaseOnlyType` here.\n".write(
            to: phasesDir.appendingPathComponent("phase-1-demo.md"),
            atomically: true, encoding: .utf8)
        // A product doc: one reference to a real test symbol, one genuinely absent.
        try "# Manual\nSee `WidgetSpecHelper` and `GenuinelyAbsentType`.\n".write(
            to: dir.appendingPathComponent("Manual.md"),
            atomically: true, encoding: .utf8)

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: dir.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "BogusPhaseOnlyType" },
                       "identifiers inside phases/ docs must not be flagged")
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "WidgetSpecHelper" },
                       "a doc reference to a symbol declared in a test file is not stale")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "GenuinelyAbsentType" },
                      "a genuinely absent symbol must still be flagged (control)")
    }
}
