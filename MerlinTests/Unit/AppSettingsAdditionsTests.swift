import XCTest
@testable import Merlin

@MainActor
final class AppSettingsAdditionsTests: XCTestCase {

    private var tempFile: URL!

    override func setUp() {
        super.setUp()
        tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
        super.tearDown()
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
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertTrue(settings2.keepAwake)
    }

    func testRoundTripPersistsPermissionMode() async throws {
        let settings = AppSettings()
        settings.defaultPermissionMode = .plan
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertEqual(settings2.defaultPermissionMode, .plan)
    }

    func testRoundTripPersistsNotificationsEnabled() async throws {
        let settings = AppSettings()
        settings.notificationsEnabled = false
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertFalse(settings2.notificationsEnabled)
    }

    func testRoundTripPersistsMessageDensity() async throws {
        let settings = AppSettings()
        settings.messageDensity = .compact
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
