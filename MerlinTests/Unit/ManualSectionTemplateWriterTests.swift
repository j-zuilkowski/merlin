import XCTest
@testable import Merlin

final class ManualSectionTemplateWriterTests: XCTestCase {

    private func makeGap(surface: String) -> ManualCoverageGap {
        ManualCoverageGap(surface: surface, surfaceType: "slash_command",
                          firstSeen: Date(), suggestedSection: nil)
    }

    // MARK: - write appends a markdown section

    func testWriteAppendsSection() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-\(UUID()).md")
        try "# User Manual\n\n".write(to: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: docFile) }

        let writer = ManualSectionTemplateWriter()
        try await writer.write(gap: makeGap(surface: "SkillRegistry.register(\"dark-mode\")"),
                               to: docFile.path)

        let text = try String(contentsOf: docFile, encoding: .utf8)
        XCTAssertTrue(text.contains("dark-mode") || text.contains("SkillRegistry"),
                      "Section should contain the surface name")
        XCTAssertTrue(text.count > 20, "Section should be non-empty")
    }

    // MARK: - write does not duplicate on second call

    func testWriteDoesNotDuplicate() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-\(UUID()).md")
        try "# User Manual\n\n".write(to: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: docFile) }

        let writer = ManualSectionTemplateWriter()
        let gap = makeGap(surface: "SomeFeature")
        try await writer.write(gap: gap, to: docFile.path)
        try await writer.write(gap: gap, to: docFile.path)

        let text = try String(contentsOf: docFile, encoding: .utf8)
        let count = text.components(separatedBy: "SomeFeature").count - 1
        XCTAssertEqual(count, 1, "Surface should appear exactly once in doc")
    }
}
