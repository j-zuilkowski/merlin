# Phase 116a — LoRA AppSettings Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 115b complete: critic-gated memory write in place.

Current state: AppSettings has no LoRA-related properties. V6 introduces local LoRA
self-training via MLX-LM on the M4 Mac (128 GB unified memory). All LoRA behaviour is
opt-in behind a master toggle; the app builds and runs cleanly with every setting at its
default (all off / empty).

New surface introduced in phase 116b:
  - `AppSettings.loraEnabled: Bool` — master switch; default false
  - `AppSettings.loraAutoTrain: Bool` — trigger training when threshold reached; default false
  - `AppSettings.loraAutoLoad: Bool` — route execute slot through adapter server; default false
  - `AppSettings.loraMinSamples: Int` — records needed before auto-train fires; default 50
  - `AppSettings.loraBaseModel: String` — MLX model ID or path; default ""
    e.g. "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
  - `AppSettings.loraAdapterPath: String` — adapter output directory; default ""
    e.g. "/Users/jon/.merlin/lora/adapter"
  - `AppSettings.loraServerURL: String` — mlx_lm.server endpoint; default ""
    e.g. "http://localhost:8080"
  - All seven keys serialised into / parsed from config.toml under a [lora] section;
    section omitted entirely when all values are at default.

TDD coverage:
  File 1 — LoRASettingsTests: defaults; TOML round-trip for each field; section omitted
            when all default; loraAutoTrain and loraAutoLoad ignored when loraEnabled false
            (TOML omits sub-toggles when master is off).

---

## Write to: MerlinTests/Unit/LoRASettingsTests.swift

```swift
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
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AppSettings.loraEnabled` (and the other six properties) not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRASettingsTests.swift
git commit -m "Phase 116a — LoRASettingsTests (failing)"
```
