import XCTest
@testable import Merlin

@MainActor
final class AppSettingsAdditionsTests: XCTestCase {

    private func makeTempFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
    }

    func testDefaultValues() {
        let settings = AppSettings()
        XCTAssertFalse(settings.keepAwake)
        XCTAssertEqual(settings.defaultPermissionMode, .ask)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertEqual(settings.messageDensity, .comfortable)
    }

    func testRoundTripPersistsKeepAwake() async throws {
        let settings = AppSettings()
        settings.keepAwake = true
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertTrue(settings2.keepAwake)
    }

    func testRoundTripPersistsPermissionMode() async throws {
        let settings = AppSettings()
        settings.defaultPermissionMode = .plan
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertEqual(settings2.defaultPermissionMode, .plan)
    }

    func testRoundTripPersistsNotificationsEnabled() async throws {
        let settings = AppSettings()
        settings.notificationsEnabled = false
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertFalse(settings2.notificationsEnabled)
    }

    func testRoundTripPersistsMessageDensity() async throws {
        let settings = AppSettings()
        settings.messageDensity = .compact
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertEqual(settings2.messageDensity, .compact)
    }

    func testMessageDensityAllCases() {
        XCTAssertEqual(MessageDensity.allCases.count, 3)
        XCTAssertTrue(MessageDensity.allCases.contains(.compact))
        XCTAssertTrue(MessageDensity.allCases.contains(.comfortable))
        XCTAssertTrue(MessageDensity.allCases.contains(.spacious))
    }
}
