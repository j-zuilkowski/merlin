import XCTest
@testable import Merlin

@MainActor
final class AppSettingsCAGTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-cag-test-\(UUID().uuidString).toml")
        return AppSettings(configURL: tmp)
    }

    func testCAGSettingsDefaults() {
        let settings = makeSettings()
        XCTAssertFalse(settings.cagEnabled)
        XCTAssertTrue(settings.cagPinClaudeMD)
        XCTAssertEqual(settings.cagPinnedPhaseDocs, [])
    }

    func testCAGSettingsRoundTrip() throws {
        let settings = makeSettings()
        settings.cagEnabled = true
        settings.cagPinClaudeMD = false
        settings.cagPinnedPhaseDocs = ["phases/phase-341a-cag-foundation-tests.md"]

        try settings.save()

        let disk = try String(contentsOf: settings.configURL, encoding: .utf8)
        XCTAssertTrue(disk.contains("[cag]"))
        XCTAssertTrue(disk.contains("enabled = true"))
        XCTAssertTrue(disk.contains("pin_claude_md = false"))
        XCTAssertTrue(disk.contains("pinned_phase_docs = [\"phases/phase-341a-cag-foundation-tests.md\"]"))

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertTrue(reloaded.cagEnabled)
        XCTAssertFalse(reloaded.cagPinClaudeMD)
        XCTAssertEqual(reloaded.cagPinnedPhaseDocs, ["phases/phase-341a-cag-foundation-tests.md"])
    }

    func testCAGSettingsLoadFromTomlSection() {
        let settings = makeSettings()
        settings.applyTOML("""
        [cag]
        enabled = true
        pin_claude_md = false
        pinned_phase_docs = ["phases/phase-341a-cag-foundation-tests.md"]
        """)

        XCTAssertTrue(settings.cagEnabled)
        XCTAssertFalse(settings.cagPinClaudeMD)
        XCTAssertEqual(settings.cagPinnedPhaseDocs, ["phases/phase-341a-cag-foundation-tests.md"])
    }
}
