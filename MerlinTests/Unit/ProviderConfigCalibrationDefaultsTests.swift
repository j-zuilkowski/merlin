import XCTest
@testable import Merlin

/// Per-provider calibration-readiness invariants.
///
/// Merlin doesn't hardcode a model per local provider — the user selects from the
/// **Settings → Providers** picker, which is populated at runtime by
/// `registry.fetchAllModels()` probing each provider's `/v1/models` endpoint.
/// These tests pin the **picker contract** rather than any specific model string:
///
/// 1. No local provider ships with an opinionated model default — the field is
///    empty, so the picker UI takes over once `fetchAllModels()` discovers the
///    served models.
/// 2. `ProviderRegistry` exposes the discovery surface required by the picker
///    (`modelsByProviderID` keyed by provider id, populated via `fetchAllModels`).
/// 3. Wire-level invariants that prevent providers from coexisting are enforced
///    statically — the Mistral.rs / LM Studio port-1234 collision is the live
///    example.
final class ProviderConfigCalibrationDefaultsTests: XCTestCase {

    private var localProviders: [ProviderConfig] {
        ProviderRegistry.defaultProviders.filter(\.isLocal)
    }

    private func provider(_ id: String) -> ProviderConfig? {
        ProviderRegistry.defaultProviders.first { $0.id == id }
    }

    // MARK: - No hardcoded model defaults (Settings picker is the source of truth)

    func testEveryUntestedLocalProviderHasEmptyModelDefault() {
        for id in ["ollama", "jan", "localai", "mistralrs", "vllm"] {
            guard let p = provider(id) else {
                XCTFail("Provider \(id) missing from defaultProviders")
                continue
            }
            XCTAssertTrue(p.model.isEmpty,
                          "\(id) must default to an empty model — the Settings → Providers picker is the source of truth, populated by registry.fetchAllModels() at runtime. Hardcoding a default opinionates a model the user may not have loaded.")
        }
    }

    // MARK: - Picker discovery surface exists

    @MainActor
    func testProviderRegistryExposesModelsByProviderID() {
        let registry = ProviderRegistry(persistURL: tempPersistURL())
        // The picker reads from this dictionary; key existence is enough to
        // confirm the surface is wired. Population happens at runtime via
        // fetchAllModels(), which probes each provider's /v1/models endpoint.
        _ = registry.modelsByProviderID
    }

    // MARK: - Mistral.rs / LM Studio port collision (wire-level invariant)

    func testMistralRSDoesNotCollideWithLMStudioPort() {
        let mistralrs = provider("mistralrs")?.baseURL ?? ""
        let lmstudio = provider("lmstudio")?.baseURL ?? ""
        XCTAssertNotEqual(mistralrs, lmstudio,
                          "mistralrs and lmstudio share a default baseURL; one daemon will fail to bind on launch")
    }

    func testMistralRSBaseURLUsesPort1235() {
        let mistralrs = provider("mistralrs")?.baseURL ?? ""
        XCTAssertTrue(mistralrs.contains(":1235/"),
                      "mistralrs default baseURL must be :1235 to avoid the LM Studio :1234 collision; was \(mistralrs)")
    }

    // MARK: - Helpers

    private func tempPersistURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
    }
}
