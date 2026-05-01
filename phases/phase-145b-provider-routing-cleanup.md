# Phase 145b — Provider Routing Cleanup

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 145a complete: failing tests in place.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Delete the three hardcoded provider properties

Remove:
```swift
    var proProvider: any LLMProvider
    var flashProvider: any LLMProvider
    private var visionProvider: any LLMProvider
```

### 2. Delete the convenience init that accepts them

Remove the entire block:
```swift
    convenience init(proProvider: any LLMProvider,
                     flashProvider: any LLMProvider,
                     visionProvider: any LLMProvider,
                     toolRouter: ToolRouter,
                     contextManager: ContextManager,
                     xcalibreClient: (any XcalibreClientProtocol)? = nil,
                     memoryBackend: (any MemoryBackendPlugin)? = nil) {
        ...
    }
```

### 3. Remove initialisation of the three properties from the designated init

In `init(slotAssignments:registry:toolRouter:contextManager:...)`, remove:
```swift
        self.proProvider = NullProvider()
        self.flashProvider = NullProvider()
        self.visionProvider = NullProvider()
```

### 4. Rewrite `provider(for:)` to use registry exclusively

```swift
    func provider(for slot: AgentSlot) -> (any LLMProvider)? {
        let effectiveSlot: AgentSlot = (slot == .orchestrate && slotAssignments[.orchestrate] == nil)
            ? .reason : slot

        if let providerID = slotAssignments[effectiveSlot], !providerID.isEmpty,
           let resolved = registry?.provider(for: providerID) {
            return resolved
        }

        // No slot assignment — fall back to the registry's active primary provider
        return registry?.primaryProvider ?? NullProvider()
    }
```

### 5. Rewrite `selectProvider(for:)`

```swift
    private func selectProvider(for message: String) -> any LLMProvider {
        let slot = selectSlot(for: message)
        return provider(for: slot) ?? registry?.primaryProvider ?? NullProvider()
    }
```

### 6. Update `setRegistryForTesting`

The helper now creates a minimal `ProviderRegistry` wrapping the provider rather than setting
three named properties:

```swift
    func setRegistryForTesting(provider: any LLMProvider) {
        let config = ProviderConfig(
            id: provider.id,
            displayName: provider.id,
            baseURL: provider.baseURL.absoluteString,
            model: "",
            isEnabled: true,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )
        let reg = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-test-registry-\(UUID().uuidString).json"),
            initialProviders: [config]
        )
        reg.add(provider)
        reg.activeProviderID = provider.id
        self.registry = reg
    }
```

Also update `makeForTesting(provider:)` in the test extension to call `engine.setRegistryForTesting(provider:)` instead of the old three-property form.

### 7. Remove LoRA special case that referenced `proProvider`

Find:
```swift
        case .execute:
            return loraProvider ?? proProvider
```
Replace with:
```swift
        case .execute:
            if let lora = loraProvider { return lora }
            // falls through to registry lookup above
```
(Move this check to the top of `provider(for:)` before the slot assignment lookup:)
```swift
    func provider(for slot: AgentSlot) -> (any LLMProvider)? {
        // LoRA provider overrides execute slot when active
        if slot == .execute, let lora = loraProvider { return lora }
        // ... rest of implementation
    }
```

---

## Edit: Merlin/App/AppState.swift

### Simplify `syncEngineProviders()`

Replace the existing body with:

```swift
    private func syncEngineProviders() {
        engine.registry = registry
        engine.slotAssignments = AppSettings.shared.slotAssignments
        activeProviderID = registry.activeProviderID
        if let activeConfig = registry.activeConfig, activeConfig.isLocal {
            activeLocalProviderID = activeConfig.localModelManagerID ?? activeConfig.id
        } else {
            activeLocalProviderID = nil
        }
        Task { await DomainRegistry.shared.setActiveDomain(id: AppSettings.shared.activeDomainID) }
        Task { [weak self] in await self?.refreshParameterAdvisories() }
    }
```

Remove the DeepSeek fallback variables (`fallbackPro`, `fallbackFlash`) — they no longer exist.

### Fix the engine init call site in AppState

Find the engine initialisation (likely in `init` or the lazy property) that still passes
`proProvider:`, `flashProvider:`, `visionProvider:`. Switch to the designated init:

```swift
        engine = AgenticEngine(
            slotAssignments: AppSettings.shared.slotAssignments,
            registry: registry,
            toolRouter: toolRouter,
            contextManager: contextManager
        )
```

---

## Edit: Merlin/Providers/ProviderConfig.swift

### Delete `visionProvider` computed property

Remove:
```swift
    var visionProvider: (any LLMProvider)? {
        let candidate = providers.first { $0.isEnabled && $0.isLocal && $0.supportsVision }
            ?? providers.first { $0.isEnabled && $0.supportsVision }
        return candidate.map { makeLLMProvider(for: $0) }
    }
```

Vision routing is now exclusively through `slotAssignments[.vision]`. No automatic vision
provider selection — the user assigns it explicitly in settings.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProviderRoutingCleanup|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all ProviderRoutingCleanupTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift \
        Merlin/Providers/ProviderConfig.swift
git commit -m "Phase 145b — Remove proProvider/flashProvider/visionProvider, simplify routing"
```
