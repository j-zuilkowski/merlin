import XCTest

/// Phase 302a - failing tests: the app Info.plist must declare the Speech and
/// microphone usage strings required for voice dictation under hardened runtime.
final class InfoPlistPermissionsTests: XCTestCase {

    /// Loads `Merlin/Info.plist` from the repo source tree, located relative to this
    /// test file (the test bundle's own Info.plist does not carry the app's keys).
    private func appInfoPlist() throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
        let plistURL = repoRoot.appendingPathComponent("Merlin/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return (plist as? [String: Any]) ?? [:]
    }

    func testInfoPlistDeclaresSpeechRecognitionUsage() throws {
        let value = try appInfoPlist()["NSSpeechRecognitionUsageDescription"] as? String
        XCTAssertNotNil(value, "Info.plist must declare NSSpeechRecognitionUsageDescription")
        XCTAssertFalse((value ?? "").isEmpty, "the usage string must be non-empty")
    }

    func testInfoPlistDeclaresMicrophoneUsage() throws {
        let value = try appInfoPlist()["NSMicrophoneUsageDescription"] as? String
        XCTAssertNotNil(value, "Info.plist must declare NSMicrophoneUsageDescription")
        XCTAssertFalse((value ?? "").isEmpty, "the usage string must be non-empty")
    }
}
