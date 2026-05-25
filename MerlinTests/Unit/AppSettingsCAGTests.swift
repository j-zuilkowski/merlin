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
        XCTAssertTrue(settings.cagPinConstitution)
        XCTAssertEqual(settings.cagPinnedTaskDocs, [])
    }

    func testCAGSettingsRoundTrip() throws {
        let settings = makeSettings()
        settings.cagEnabled = true
        settings.cagPinConstitution = false
        settings.cagPinnedTaskDocs = ["tasks/task-341a-cag-foundation-tests.md"]

        try settings.save()

        let disk = try String(contentsOf: settings.configURL, encoding: .utf8)
        XCTAssertTrue(disk.contains("[cag]"))
        XCTAssertTrue(disk.contains("enabled = true"))
        XCTAssertTrue(disk.contains("pin_constitution = false"))
        XCTAssertTrue(disk.contains("pinned_task_docs = [\"tasks/task-341a-cag-foundation-tests.md\"]"))

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertTrue(reloaded.cagEnabled)
        XCTAssertFalse(reloaded.cagPinConstitution)
        XCTAssertEqual(reloaded.cagPinnedTaskDocs, ["tasks/task-341a-cag-foundation-tests.md"])
    }

    func testCAGSettingsLoadFromTomlSection() {
        let settings = makeSettings()
        settings.applyTOML("""
        [cag]
        enabled = true
        pin_constitution = false
        pinned_task_docs = ["tasks/task-341a-cag-foundation-tests.md"]
        """)

        XCTAssertTrue(settings.cagEnabled)
        XCTAssertFalse(settings.cagPinConstitution)
        XCTAssertEqual(settings.cagPinnedTaskDocs, ["tasks/task-341a-cag-foundation-tests.md"])
    }

    func testLlamaCppRuntimeSettingsRoundTrip() throws {
        let settings = makeSettings()
        try? KeychainManager.deleteAPIKey(for: "llamacpp")
        settings.llamaCppRuntime.serverPath = "/opt/homebrew/bin/llama-server"
        settings.llamaCppRuntime.routerEnabled = true
        settings.llamaCppRuntime.modelsDir = "/Models/gguf"
        settings.llamaCppRuntime.modelsPresetPath = "/tmp/router.ini"
        settings.llamaCppRuntime.modelPath = "/Models/general.gguf"
        settings.llamaCppRuntime.mmprojPath = "/Models/mmproj.gguf"
        settings.llamaCppRuntime.parallelSlots = 2
        settings.llamaCppRuntime.ubatchSize = 256
        settings.llamaCppRuntime.autoloadModels = false

        try settings.save()

        let disk = try String(contentsOf: settings.configURL, encoding: .utf8)
        XCTAssertTrue(disk.contains("[llamacpp]"))
        XCTAssertTrue(disk.contains("models_dir = \"/Models/gguf\""))
        XCTAssertTrue(disk.contains("parallel_slots = 2"))
        XCTAssertTrue(disk.contains("autoload_models = false"))
        XCTAssertFalse(disk.contains("api_key"))

        let reloaded = AppSettings(configURL: settings.configURL)
        XCTAssertEqual(reloaded.llamaCppRuntime.modelsDir, "/Models/gguf")
        XCTAssertEqual(reloaded.llamaCppRuntime.parallelSlots, 2)
        XCTAssertEqual(reloaded.llamaCppRuntime.ubatchSize, 256)
        XCTAssertFalse(reloaded.llamaCppRuntime.autoloadModels)
        try? KeychainManager.deleteAPIKey(for: "llamacpp")
    }

    func testLlamaCppLegacyAPIKeyMigratesOutOfConfig() throws {
        try? KeychainManager.deleteAPIKey(for: "llamacpp")
        let settings = makeSettings()
        settings.applyTOML("""
        [llamacpp]
        api_key = "local-router-token"
        """)

        XCTAssertEqual(KeychainManager.readAPIKey(for: "llamacpp"), "local-router-token")
        XCTAssertTrue(settings.llamaCppRuntime.apiKey.isEmpty)
        try? KeychainManager.deleteAPIKey(for: "llamacpp")
    }
}
