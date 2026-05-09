import XCTest
@testable import Merlin

@MainActor
final class AppSettingsKAGTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        // Use a temp config path so we don't pollute the real ~/.merlin/config.toml
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-kag-test-\(UUID().uuidString).toml")
        return AppSettings(configURL: tmp)
    }

    func test_kagEnabled_defaults_false() {
        let settings = makeSettings()
        XCTAssertFalse(settings.kagEnabled)
    }

    func test_kagHops_defaults_2() {
        let settings = makeSettings()
        XCTAssertEqual(settings.kagHops, 2)
    }

    func test_kagXcalibreURL_defaults_empty() {
        let settings = makeSettings()
        XCTAssertTrue(settings.kagXcalibreURL.isEmpty)
    }

    func test_kagEnabled_roundtrip() throws {
        let settings = makeSettings()
        settings.kagEnabled = true
        try settings.save()

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertTrue(reloaded.kagEnabled)
    }

    func test_kagHops_roundtrip() throws {
        let settings = makeSettings()
        settings.kagHops = 3
        try settings.save()

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertEqual(reloaded.kagHops, 3)
    }
}
