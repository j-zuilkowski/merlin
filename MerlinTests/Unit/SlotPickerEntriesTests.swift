import XCTest
@testable import Merlin

@MainActor
final class SlotPickerEntriesTests: XCTestCase {

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
            ProviderConfig(id: "ollama",
                           displayName: "Ollama",
                           baseURL: "http://localhost:11434/v1",
                           model: "",
                           isEnabled: false, isLocal: true,  // disabled
                           supportsThinking: false, supportsVision: false,
                           kind: .openAICompatible),
        ]
        let reg = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-picker-\(UUID().uuidString).json"),
            initialProviders: providers
        )
        for (id, modelList) in models {
            reg.modelsByProviderID[id] = modelList
        }
        return reg
    }

    // MARK: - Basic contents

    func testPlainIDsForEnabledProvidersAreIncluded() {
        let registry = makeRegistry()
        let entries = registry.allSlotPickerEntries

        let ids = entries.map(\.id)
        XCTAssertTrue(ids.contains("deepseek"))
        XCTAssertTrue(ids.contains("lmstudio"))
    }

    func testDisabledProvidersAreExcluded() {
        let registry = makeRegistry()
        let entries = registry.allSlotPickerEntries

        let ids = entries.map(\.id)
        XCTAssertFalse(ids.contains("ollama"), "Disabled provider must not appear in slot picker")
    }

    func testDisplayNamesAreCorrect() {
        let registry = makeRegistry()
        let entries = registry.allSlotPickerEntries

        let deepseekEntry = entries.first { $0.id == "deepseek" }
        XCTAssertEqual(deepseekEntry?.displayName, "DeepSeek")

        let lmstudioEntry = entries.first { $0.id == "lmstudio" }
        XCTAssertEqual(lmstudioEntry?.displayName, "LM Studio")
    }

    // MARK: - Virtual entries

    func testVirtualEntriesAppearWhenModelsLoaded() {
        let registry = makeRegistry(models: ["lmstudio": ["Qwen2.5-VL-72B", "phi-4"]])
        let entries = registry.allSlotPickerEntries

        let ids = entries.map(\.id)
        XCTAssertTrue(ids.contains("lmstudio:Qwen2.5-VL-72B"))
        XCTAssertTrue(ids.contains("lmstudio:phi-4"))
    }

    func testVirtualEntryDisplayNames() {
        let registry = makeRegistry(models: ["lmstudio": ["phi-4"]])
        let entries = registry.allSlotPickerEntries

        let virtual = entries.first { $0.id == "lmstudio:phi-4" }
        XCTAssertEqual(virtual?.displayName, "LM Studio — phi-4")
        XCTAssertEqual(virtual?.isVirtual, true)
    }

    func testPlainEntryIsNotVirtual() {
        let registry = makeRegistry()
        let entries = registry.allSlotPickerEntries

        let plain = entries.first { $0.id == "deepseek" }
        XCTAssertEqual(plain?.isVirtual, false)
    }

    func testNoVirtualEntriesWhenModelsNotFetched() {
        let registry = makeRegistry()  // no models loaded
        let entries = registry.allSlotPickerEntries

        let virtual = entries.filter(\.isVirtual)
        XCTAssertTrue(virtual.isEmpty, "No virtual entries before fetchAllModels runs")
    }

    // MARK: - Ordering

    func testPlainIDsComeBeforeVirtualEntries() {
        let registry = makeRegistry(models: ["lmstudio": ["phi-4"]])
        let entries = registry.allSlotPickerEntries

        let plainIndices   = entries.indices.filter { !entries[$0].isVirtual }
        let virtualIndices = entries.indices.filter {  entries[$0].isVirtual }

        guard let lastPlain = plainIndices.max(),
              let firstVirtual = virtualIndices.min() else {
            // If there are no virtual entries this test is vacuously satisfied
            return
        }
        XCTAssertLessThan(lastPlain, firstVirtual,
                          "All plain entries must appear before virtual entries")
    }

    func testVirtualEntriesGroupedByBackend() {
        let registry = makeRegistry(models: [
            "lmstudio": ["phi-4", "Qwen2.5-VL-72B"],
        ])
        let entries = registry.allSlotPickerEntries
        let virtualIDs = entries.filter(\.isVirtual).map(\.id)

        // Both lmstudio virtual entries should appear consecutively
        let lmIndices = virtualIDs.indices.filter { virtualIDs[$0].hasPrefix("lmstudio:") }
        if lmIndices.count == 2 {
            XCTAssertEqual(lmIndices[1] - lmIndices[0], 1,
                           "Virtual entries for the same backend must be consecutive")
        }
    }

    // MARK: - Count

    func testTotalCountIsCorrect() {
        // 2 enabled providers + 2 virtual entries for lmstudio = 4
        let registry = makeRegistry(models: ["lmstudio": ["phi-4", "qwen"]])
        let entries = registry.allSlotPickerEntries

        XCTAssertEqual(entries.count, 4)
    }
}
