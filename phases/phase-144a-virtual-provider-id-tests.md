# Phase 144a — Virtual Provider ID Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 143b complete: dynamic model fetching in place.

New surface introduced in phase 144b:
  - `ProviderRegistry.provider(for:)` resolves virtual IDs in `"backendID:modelID"` format.
    `"lmstudio:phi-4"` returns an `OpenAICompatibleProvider` using lmstudio's `baseURL` and
    `phi-4` as the `modelID`. The backend entry must be present and enabled.
  - `ProviderRegistry.virtualProviderIDs(for:)` — returns the full set of addressable IDs for a
    local backend: `["lmstudio", "lmstudio:Qwen2.5-VL", "lmstudio:phi-4"]` given two loaded models.
  - `ProviderRegistry.displayName(for:)` — resolves a human-readable label for any provider ID
    including virtual ones: `"lmstudio:phi-4"` → `"LM Studio — phi-4"`.
  - `LMStudioProvider.swift` is deleted. The special-case `lmstudio` branch in `makeLLMProvider`
    is removed; an empty `model` string is passed through as-is (LMStudio uses the loaded model).

TDD coverage:
  File 1 — VirtualProviderIDTests: verify resolution, display name, and error cases

---

## Write to: MerlinTests/Unit/VirtualProviderIDTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class VirtualProviderIDTests: XCTestCase {

    private func makeRegistry() -> ProviderRegistry {
        let providers: [ProviderConfig] = [
            ProviderConfig(id: "lmstudio",
                           displayName: "LM Studio",
                           baseURL: "http://localhost:1234/v1",
                           model: "",
                           isEnabled: true,
                           isLocal: true,
                           supportsThinking: false,
                           supportsVision: true,
                           kind: .openAICompatible),
            ProviderConfig(id: "deepseek",
                           displayName: "DeepSeek",
                           baseURL: "https://api.deepseek.com/v1",
                           model: "deepseek-chat",
                           isEnabled: true,
                           isLocal: false,
                           supportsThinking: true,
                           supportsVision: false,
                           kind: .openAICompatible),
        ]
        return ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-virt-\(UUID().uuidString).json"),
            initialProviders: providers
        )
    }

    // MARK: - Virtual ID resolution

    func testVirtualIDResolvesToCorrectBaseURL() throws {
        let registry = makeRegistry()
        registry.modelsByProviderID["lmstudio"] = ["Qwen2.5-VL-72B", "phi-4"]

        let provider = registry.provider(for: "lmstudio:phi-4")

        XCTAssertNotNil(provider, "Virtual ID should resolve to a provider")
        XCTAssertEqual(provider?.baseURL, URL(string: "http://localhost:1234/v1"))
    }

    func testVirtualIDUsesModelSuffix() throws {
        let registry = makeRegistry()
        registry.modelsByProviderID["lmstudio"] = ["Qwen2.5-VL-72B", "phi-4"]

        let provider = registry.provider(for: "lmstudio:Qwen2.5-VL-72B")

        XCTAssertNotNil(provider)
        // The provider's id encodes the virtual ID so routing telemetry is accurate
        XCTAssertEqual(provider?.id, "lmstudio:Qwen2.5-VL-72B")
    }

    func testVirtualIDReturnsNilForUnknownBackend() throws {
        let registry = makeRegistry()

        let provider = registry.provider(for: "nosuchthing:phi-4")

        XCTAssertNil(provider)
    }

    func testVirtualIDReturnsNilForDisabledBackend() throws {
        let providers: [ProviderConfig] = [
            ProviderConfig(id: "lmstudio",
                           displayName: "LM Studio",
                           baseURL: "http://localhost:1234/v1",
                           model: "",
                           isEnabled: false,  // disabled
                           isLocal: true,
                           supportsThinking: false,
                           supportsVision: true,
                           kind: .openAICompatible),
        ]
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-virt2-\(UUID().uuidString).json"),
            initialProviders: providers
        )
        registry.modelsByProviderID["lmstudio"] = ["phi-4"]

        let provider = registry.provider(for: "lmstudio:phi-4")

        XCTAssertNil(provider, "Virtual ID for disabled backend should return nil")
    }

    func testPlainIDStillWorks() throws {
        let registry = makeRegistry()

        let provider = registry.provider(for: "deepseek")

        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.id, "deepseek")
    }

    // MARK: - virtualProviderIDs(for:)

    func testVirtualProviderIDsIncludesBaseAndModelEntries() throws {
        let registry = makeRegistry()
        registry.modelsByProviderID["lmstudio"] = ["Qwen2.5-VL-72B", "phi-4"]

        let ids = registry.virtualProviderIDs(for: "lmstudio")

        XCTAssertTrue(ids.contains("lmstudio"),           "Base ID must be included")
        XCTAssertTrue(ids.contains("lmstudio:Qwen2.5-VL-72B"))
        XCTAssertTrue(ids.contains("lmstudio:phi-4"))
        XCTAssertEqual(ids.count, 3)
    }

    func testVirtualProviderIDsReturnsJustBaseWhenNoModels() throws {
        let registry = makeRegistry()
        // No entry in modelsByProviderID for lmstudio

        let ids = registry.virtualProviderIDs(for: "lmstudio")

        XCTAssertEqual(ids, ["lmstudio"])
    }

    func testVirtualProviderIDsReturnsEmptyForUnknownID() throws {
        let registry = makeRegistry()

        let ids = registry.virtualProviderIDs(for: "nonexistent")

        XCTAssertTrue(ids.isEmpty)
    }

    // MARK: - displayName(for:)

    func testDisplayNameForPlainID() throws {
        let registry = makeRegistry()

        XCTAssertEqual(registry.displayName(for: "deepseek"), "DeepSeek")
        XCTAssertEqual(registry.displayName(for: "lmstudio"), "LM Studio")
    }

    func testDisplayNameForVirtualID() throws {
        let registry = makeRegistry()

        XCTAssertEqual(registry.displayName(for: "lmstudio:phi-4"), "LM Studio — phi-4")
        XCTAssertEqual(registry.displayName(for: "lmstudio:Qwen2.5-VL-72B"),
                       "LM Studio — Qwen2.5-VL-72B")
    }

    func testDisplayNameForUnknownIDFallsBackToID() throws {
        let registry = makeRegistry()

        XCTAssertEqual(registry.displayName(for: "mystery-provider"), "mystery-provider")
    }

    // MARK: - LMStudioProvider deleted

    func testLMStudioProviderClassIsGone() {
        // Compilation-only assertion. If LMStudioProvider still exists this file will not compile.
        // The test body is intentionally empty.
        let _: Void = ()
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `virtualProviderIDs(for:)`, `displayName(for:)` not yet defined;
`provider(for:)` does not yet handle `":"` format.

## Commit
```bash
git add MerlinTests/Unit/VirtualProviderIDTests.swift
git commit -m "Phase 144a — Virtual provider ID tests (failing)"
```
