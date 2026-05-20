import XCTest
@testable import Merlin

/// Pins the `loraServingTarget` AppSettings field that selects which MLX-native
/// runtime serves the trained LoRA adapter. Default is `"mlx_lm_server"` — the
/// historic routing target. Alternatives: `"vllm_metal"`, `"lm_studio"`,
/// `"custom"` (when the user wires a runtime not in the known set).
///
/// Routing itself still flows through `loraServerURL` — this field exists for
/// UI guidance + future per-target defaults, not for switching protocol.
@MainActor
final class LoRAServingTargetSettingsTests: XCTestCase {

    func testDefaultIsMLXLMServer() {
        let settings = AppSettings()
        XCTAssertEqual(settings.loraServingTarget, "mlx_lm_server",
                       "Historic Merlin default is mlx_lm.server; preserve it as the unset value.")
    }

    func testTOMLRoundTripForNonDefault() {
        let settings = AppSettings()
        settings.loraEnabled = true
        settings.loraServingTarget = "vllm_metal"
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("lora_serving_target = \"vllm_metal\""),
                      "TOML must serialise non-default loraServingTarget")

        let restored = AppSettings()
        restored.applyTOML(toml)
        XCTAssertEqual(restored.loraServingTarget, "vllm_metal",
                       "TOML round-trip must restore loraServingTarget")
    }

    func testTOMLOmittedWhenDefault() {
        let settings = AppSettings()
        settings.loraEnabled = true
        // loraServingTarget at default — should not appear in serialised TOML
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("lora_serving_target"),
                       "Default value of loraServingTarget must be omitted from TOML")
    }

    func testSupportedTargetSet() {
        // The runtime enforces a known set of strings via static
        // ProviderConfig surfaces; this test pins the canonical list so the
        // picker UI and AppSettings stay in sync.
        let expected = Set(["mlx_lm_server", "vllm_metal", "lm_studio", "custom"])
        XCTAssertEqual(Set(AppSettings.knownLoRAServingTargets), expected,
                       "If new MLX runtimes are added, update both AppSettings.knownLoRAServingTargets and this assertion.")
    }
}
