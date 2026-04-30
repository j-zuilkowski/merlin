import XCTest
@testable import Merlin

@MainActor
final class LoRASettingsTests: XCTestCase {

    // MARK: - Defaults

    func testLoRADefaultsAllOff() {
        // loraEnabled is the gating property; BUILD FAILED until 116b adds it.
        XCTAssertFalse(AppSettings.shared.loraEnabled)
        XCTAssertFalse(AppSettings.shared.loraAutoTrain)
        XCTAssertFalse(AppSettings.shared.loraAutoLoad)
        XCTAssertEqual(AppSettings.shared.loraMinSamples, 50)
        XCTAssertTrue(AppSettings.shared.loraBaseModel.isEmpty)
        XCTAssertTrue(AppSettings.shared.loraAdapterPath.isEmpty)
        XCTAssertTrue(AppSettings.shared.loraServerURL.isEmpty)
    }

    // MARK: - TOML omitted when all default

    func testLoRASectionOmittedWhenAllDefault() {
        let settings = AppSettings()
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("[lora]"),
                       "[lora] section must be absent when all values are default")
    }

    // MARK: - TOML round-trips

    func testLoRAEnabledRoundTrip() {
        let settings = AppSettings()
        settings.loraEnabled = true
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_enabled = true"))

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertTrue(restored.loraEnabled)
    }

    func testLoRAAutoTrainWrittenOnlyWhenEnabled() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraAutoTrain = true
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_auto_train = true"))

        // loraAutoTrain should NOT appear when loraEnabled is false
        let settingsOff = AppSettings()
        settingsOff.loraEnabled = false
        settingsOff.loraAutoTrain = true          // set but master is off
        let tomlOff = settingsOff.serializedTOML()
        XCTAssertFalse(tomlOff.contains("lora_auto_train"),
                       "lora_auto_train must be suppressed when loraEnabled = false")
    }

    func testLoRAAutoLoadWrittenOnlyWhenEnabled() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraAutoLoad = true
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_auto_load = true"))

        let settingsOff = AppSettings()
        settingsOff.loraEnabled = false
        settingsOff.loraAutoLoad = true
        let tomlOff = settingsOff.serializedTOML()
        XCTAssertFalse(tomlOff.contains("lora_auto_load"),
                       "lora_auto_load must be suppressed when loraEnabled = false")
    }

    func testLoRAMinSamplesRoundTrip() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraMinSamples = 100
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_min_samples = 100"))

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertEqual(restored.loraMinSamples, 100)
    }

    func testLoRAMinSamplesOmittedWhenDefault() {
        let settings = AppSettings()
        settings.loraEnabled = true
        // loraMinSamples is 50 (default) — omit it
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("lora_min_samples"),
                       "lora_min_samples must be omitted when value is 50 (default)")
    }

    func testLoRABaseModelRoundTrip() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraBaseModel = "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_base_model"))

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertEqual(restored.loraBaseModel, "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit")
    }

    func testLoRAAdapterPathRoundTrip() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraAdapterPath = "/Users/test/.merlin/lora/adapter"
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_adapter_path"))

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertEqual(restored.loraAdapterPath, "/Users/test/.merlin/lora/adapter")
    }

    func testLoRAServerURLRoundTrip() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraServerURL = "http://localhost:8080"
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_server_url"))

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertEqual(restored.loraServerURL, "http://localhost:8080")
    }
}
