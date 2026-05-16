import XCTest
@testable import Merlin

@MainActor
final class LocalModelPickerEntriesTests: XCTestCase {

    private func makeRegistry(models: [String: [String]] = [:]) -> ProviderRegistry {
        let providers: [ProviderConfig] = [
            ProviderConfig(id: "deepseek",
                           displayName: "DeepSeek",
                           baseURL: "https://api.deepseek.com/v1",
                           model: "deepseek-chat",
                           isEnabled: true, isLocal: false,
                           supportsThinking: true, supportsVision: false,
                           kind: .openAICompatible),
            ProviderConfig(id: "lmstudio",
                           displayName: "LM Studio",
                           baseURL: "http://localhost:1234/v1",
                           model: "",
                           isEnabled: true, isLocal: true,
                           supportsThinking: false, supportsVision: true,
                           kind: .openAICompatible),
        ]
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-local-picker-\(UUID().uuidString).json"),
            initialProviders: providers
        )
        for (id, modelList) in models {
            registry.modelsByProviderID[id] = modelList
        }
        return registry
    }

    /// A local provider with loaded models must contribute ONLY per-model virtual
    /// entries - no plain base entry whose id equals the bare backend id.
    func testLocalProviderWithModelsYieldsOnlyVirtualEntries() {
        let registry = makeRegistry(models: [
            "lmstudio": ["qwen/qwen3.6-27b", "qwen2.5-vl-72b-instruct"],
        ])

        let lmEntries = registry.allSlotPickerEntries.filter {
            $0.id == "lmstudio" || $0.id.hasPrefix("lmstudio:")
        }

        XCTAssertFalse(lmEntries.contains { $0.id == "lmstudio" },
            "the bare base entry must not be offered when models are known")
        XCTAssertEqual(Set(lmEntries.map(\.id)),
                       ["lmstudio:qwen/qwen3.6-27b", "lmstudio:qwen2.5-vl-72b-instruct"],
                       "one virtual entry per loaded model, no base entry")
        XCTAssertTrue(lmEntries.allSatisfy { $0.isVirtual },
                      "every local entry must be a virtual per-model entry")
    }

    /// A local provider with no known models keeps its plain base entry so the user
    /// can still see the backend and trigger a refresh.
    func testLocalProviderWithoutModelsYieldsBaseEntry() {
        let registry = makeRegistry(models: ["lmstudio": []])

        let lmEntries = registry.allSlotPickerEntries.filter {
            $0.id == "lmstudio" || $0.id.hasPrefix("lmstudio:")
        }

        XCTAssertEqual(lmEntries.map(\.id), ["lmstudio"],
            "with no known models, exactly the plain base entry is offered")
        XCTAssertFalse(lmEntries[0].isVirtual)
    }

    /// A remote provider always keeps its plain base entry - its base config carries a
    /// real model name. (Behaviour unchanged by phase 283b.)
    func testRemoteProviderKeepsBaseEntry() {
        let registry = makeRegistry()

        let entries = registry.allSlotPickerEntries.filter { $0.id == "deepseek" }
        XCTAssertEqual(entries.count, 1,
            "a remote provider contributes its plain base entry")
        XCTAssertFalse(entries[0].isVirtual)
    }
}
