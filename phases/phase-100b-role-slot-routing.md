# Phase 100b — AgenticEngine Role Slot Routing

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 100a complete: failing slot routing tests in place.

This phase replaces the `proProvider`/`flashProvider` two-provider model with
capability-based role slots: `execute`, `reason`, `orchestrate`, `vision`.
The `AgenticEngine` init signature changes; all call sites must be updated.

---

## Write to: Merlin/Engine/AgentSlot.swift

```swift
import Foundation

/// Capability-based role slots for the supervisor-worker architecture.
///
/// - `execute`: cheap/fast local model — bulk execution, routine tasks
/// - `reason`: thinking/reasoning model — verification, critic, high-stakes work
/// - `orchestrate`: planning model — task decomposition; defaults to `reason` if unassigned
/// - `vision`: vision-capable model — screenshot analysis, UI inspection
enum AgentSlot: String, CaseIterable, Codable, Hashable, Sendable {
    case execute
    case reason
    case orchestrate
    case vision
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

Replace the class declaration and properties:

```swift
// BEFORE:
@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let thinkingDetector = ThinkingModeDetector.self
    var proProvider: any LLMProvider
    var flashProvider: any LLMProvider
    private let visionProvider: any LLMProvider
    let toolRouter: ToolRouter
    var xcalibreClient: XcalibreClient?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var permissionMode: PermissionMode = .ask
    var claudeMDContent: String = ""
    var memoriesContent: String = ""
    var onUsageUpdate: ((Int) -> Void)?
    private var hookEngine: HookEngine {
        HookEngine(hooks: AppSettings.shared.hooks)
    }
    weak var sessionStore: SessionStore?
    private var currentTask: Task<Void, Never>?
    @Published var isRunning: Bool = false

    init(proProvider: any LLMProvider,
         flashProvider: any LLMProvider,
         visionProvider: any LLMProvider,
         toolRouter: ToolRouter,
         contextManager: ContextManager,
         xcalibreClient: XcalibreClient? = nil) {
        self.proProvider = proProvider
        self.flashProvider = flashProvider
        self.visionProvider = visionProvider
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
    }
```

```swift
// AFTER:
@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let thinkingDetector = ThinkingModeDetector.self
    let toolRouter: ToolRouter
    var xcalibreClient: XcalibreClient?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var permissionMode: PermissionMode = .ask
    var claudeMDContent: String = ""
    var memoriesContent: String = ""
    var onUsageUpdate: ((Int) -> Void)?
    private var hookEngine: HookEngine {
        HookEngine(hooks: AppSettings.shared.hooks)
    }
    weak var sessionStore: SessionStore?
    private var currentTask: Task<Void, Never>?
    @Published var isRunning: Bool = false

    /// Slot → provider ID mapping. Resolved against ProviderRegistry at call time.
    private var slotAssignments: [AgentSlot: String]

    init(slotAssignments: [AgentSlot: String] = [:],
         registry: ProviderRegistry? = nil,
         toolRouter: ToolRouter,
         contextManager: ContextManager,
         xcalibreClient: XcalibreClient? = nil) {
        self.slotAssignments = slotAssignments
        self.registry = registry
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
    }
```

Replace `selectProvider(for:)` and `modelID(for:)` with the following:

```swift
// MARK: - Slot resolution

/// Returns the provider assigned to the given slot, or nil if registry is unavailable.
/// `orchestrate` falls back to `reason` when not explicitly assigned.
func provider(for slot: AgentSlot) -> (any LLMProvider)? {
    guard let registry else { return nil }
    let effectiveSlot: AgentSlot
    if slot == .orchestrate, slotAssignments[.orchestrate] == nil {
        effectiveSlot = .reason
    } else {
        effectiveSlot = slot
    }
    guard let providerID = slotAssignments[effectiveSlot] else { return nil }
    return registry.provider(for: providerID)
}

/// Determines which slot should handle this message.
/// Checks `@slot` override annotation first, then vision keywords, then defaults to execute.
func selectSlot(for message: String) -> AgentSlot {
    let lower = message.lowercased()

    // Explicit slot override annotations
    if lower.hasPrefix("@reason ") || lower.contains(" @reason ") { return .reason }
    if lower.hasPrefix("@execute ") || lower.contains(" @execute ") { return .execute }
    if lower.hasPrefix("@orchestrate ") || lower.contains(" @orchestrate ") { return .orchestrate }

    // Vision keywords
    let visionKeywords = ["screenshot", "screen", "vision", "ui", "click", "button"]
    if visionKeywords.contains(where: { lower.contains($0) }) { return .vision }

    // Default: execute slot handles all other work
    return .execute
}

private func resolvedProvider(for slot: AgentSlot) -> any LLMProvider {
    // Fallback chain: slot → execute slot → first available provider
    if let p = provider(for: slot) { return p }
    if let p = provider(for: .execute) { return p }
    // Last resort — return a no-op provider rather than crash
    return NullProvider()
}

private func modelID(for provider: any LLMProvider) -> String {
    guard let registry else { return provider.id }
    if let config = registry.providers.first(where: { $0.id == provider.id }) {
        if config.model.isEmpty, config.id == "lmstudio" {
            return LMStudioProvider().model
        }
        return config.model.isEmpty ? provider.id : config.model
    }
    return provider.id
}
```

Replace the `runLoop` provider selection:

```swift
// BEFORE (in runLoop while loop):
let provider = selectProvider(for: userMessage)

// AFTER:
let slot = selectSlot(for: userMessage)
let provider = resolvedProvider(for: slot)
```

Remove `shouldUseThinking(for:)` in favour of the slot's thinking config:

```swift
// shouldUseThinking remains but is now consulted only for reason/orchestrate slots:
func shouldUseThinking(for message: String) -> Bool {
    if let registry, let activeConfig = registry.activeConfig {
        return activeConfig.supportsThinking && thinkingDetector.shouldEnableThinking(for: message)
    }
    return thinkingDetector.shouldEnableThinking(for: message)
}
```

In the `runLoop` `while` body, update thinking check:

```swift
// BEFORE:
thinking: shouldUseThinking(for: userMessage) ? ThinkingModeDetector.config(for: userMessage) : nil

// AFTER:
let useThinking = (slot == .reason || slot == .orchestrate) && shouldUseThinking(for: userMessage)
// ...
thinking: useThinking ? ThinkingModeDetector.config(for: userMessage) : nil
```

Update `handleSpawnAgent` to use orchestrate slot:

```swift
// BEFORE:
let provider = registry?.primaryProvider ?? proProvider

// AFTER:
let provider = resolvedProvider(for: .orchestrate)
```

---

## Write to: Merlin/Engine/NullProvider.swift

```swift
import Foundation

/// Emergency fallback provider — yields nothing, never crashes.
/// Used when no slot assignment is configured. Should not appear in normal operation.
final class NullProvider: LLMProvider {
    let id = "null"
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
```

---

## AppSettings additions (add to Merlin/Config/AppSettings.swift)

```swift
// MARK: - V5 Role Slot Assignments

/// Maps each AgentSlot to a provider ID. Empty string = unassigned (falls back per slot rules).
@Published var slotAssignments: [AgentSlot: String] = [:]
```

Load under `[slots]` TOML key in `load(from:)`:
```swift
if let slots = toml["slots"] as? [String: String] {
    var assignments: [AgentSlot: String] = [:]
    for slot in AgentSlot.allCases {
        if let providerID = slots[slot.rawValue], !providerID.isEmpty {
            assignments[slot] = providerID
        }
    }
    slotAssignments = assignments
}
```

config.toml schema:
```toml
[slots]
execute     = "mistral-7b"    # local fast model
reason      = "deepseek-r1"   # remote thinking model
orchestrate = ""              # empty = falls back to reason slot
vision      = "qwen-vl"       # local vision model
```

---

## Update all AgenticEngine call sites

Update `Merlin/App/AppState.swift` (or wherever AgenticEngine is initialised):

```swift
// BEFORE:
let engine = AgenticEngine(
    proProvider: proProvider,
    flashProvider: flashProvider,
    visionProvider: visionProvider,
    toolRouter: toolRouter,
    contextManager: contextManager
)

// AFTER:
let engine = AgenticEngine(
    slotAssignments: AppSettings.shared.slotAssignments,
    registry: providerRegistry,
    toolRouter: toolRouter,
    contextManager: contextManager
)
```

---

## project.yml additions

Add:
```yaml
- Merlin/Engine/AgentSlot.swift
- Merlin/Engine/NullProvider.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AgenticEngineSlot.*passed|AgenticEngineSlot.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; AgenticEngineSlotTests → 7 pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgentSlot.swift \
        Merlin/Engine/NullProvider.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Config/AppSettings.swift \
        project.yml
git commit -m "Phase 100b — AgenticEngine role slot routing (execute/reason/orchestrate/vision)"
```
