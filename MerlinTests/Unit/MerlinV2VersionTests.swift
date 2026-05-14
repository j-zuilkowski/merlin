import XCTest

final class MerlinV2VersionTests: XCTestCase {

    func test_projectYML_hasMarketingVersion200() throws {
        let text = try loadFile("project.yml")
        XCTAssertTrue(text.contains("MARKETING_VERSION: \"2.0.0\""))
    }

    func test_projectYML_buildNumber_isGreaterThanV191Build() throws {
        let text = try loadFile("project.yml")
        let match = try XCTUnwrap(text.firstMatch(of: /CURRENT_PROJECT_VERSION:\s*(\d+)/))
        let value = try XCTUnwrap(Int(String(match.1)))
        XCTAssertGreaterThan(value, 14)
    }

    func test_releaseNotesFile_exists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRootURL
            .appendingPathComponent("RELEASE-v2.0.0.md").path))
    }

    func test_releaseNotes_mentionsV2ElectronicsScope() throws {
        let text = try loadFile("RELEASE-v2.0.0.md")
        XCTAssertTrue(text.contains("Merlin v2.0"))
        XCTAssertTrue(text.contains("KiCad"))
        XCTAssertTrue(text.contains("FreeRouting"))
        XCTAssertTrue(text.contains("ERC"))
        XCTAssertTrue(text.contains("DRC"))
        XCTAssertTrue(text.contains("SPICE"))
        XCTAssertTrue(text.contains("BOM"))
    }

    private func loadFile(_ path: String) throws -> String {
        let fileURL = repositoryRootURL.appendingPathComponent(path)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repository root
    }
}
