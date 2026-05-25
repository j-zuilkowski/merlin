# Task 174b — Fix: add private makeEngine to LoRAProviderRoutingTests with correct slots

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 174a complete: LoRAProviderRoutingTests slot failures documented.

## Root Cause

The global `makeEngine(proProvider:flashProvider:)` in `TestHelpers/EngineFactory.swift`
assigns `[.execute: flash.id, .reason: pro.id]` — flash is execute, pro is reason.

The LoRA tests call `makeEngine(proProvider: proMock)` expecting `proMock` to be in the
`.execute` slot (so that `loraProvider` overrides it and `provider(for: .execute)` falls
back to `proMock` when loraProvider is nil). But with the global factory, `proMock` lands
in `.reason` and `provider(for: .execute)` returns the flash mock instead.

## Fix

### Edit: `MerlinTests/Unit/LoRAProviderRoutingTests.swift`

Add a private `makeEngine` override **inside** `LoRAProviderRoutingTests` that maps
`proProvider → .execute` and `flashProvider → .reason`. Insert before the first test:

```swift
// MARK: - Helpers

@MainActor
private func makeEngine(
    proProvider: MockProvider? = nil,
    flashProvider: MockProvider? = nil
) -> AgenticEngine {
    let pro   = proProvider   ?? MockProvider()
    let flash = flashProvider ?? MockProvider()

    let proConfig = ProviderConfig(
        id: pro.id, displayName: pro.id,
        baseURL: pro.baseURL.absoluteString,
        model: "", isEnabled: true, isLocal: true,
        supportsThinking: false, supportsVision: false, kind: .openAICompatible
    )
    let flashConfig = ProviderConfig(
        id: flash.id, displayName: flash.id,
        baseURL: flash.baseURL.absoluteString,
        model: "", isEnabled: true, isLocal: true,
        supportsThinking: false, supportsVision: false, kind: .openAICompatible
    )
    let registry = ProviderRegistry(
        persistURL: URL(fileURLWithPath: "/tmp/merlin-lora-\(UUID().uuidString).json"),
        initialProviders: [proConfig, flashConfig]
    )
    registry.add(pro)
    registry.add(flash)
    registry.activeProviderID = pro.id

    let memory = AuthMemory(storePath: "/tmp/auth-lora-\(UUID().uuidString).json")
    let gate   = AuthGate(memory: memory, presenter: NullAuthPresenter())

    // LoRA tests: proProvider → .execute (the slot loraProvider overrides),
    //             flashProvider → .reason
    return AgenticEngine(
        slotAssignments: [.execute: pro.id, .reason: flash.id],
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager()
    )
}
```

This private override shadows the global `makeEngine` for calls within this test class.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRAProvider.*passed|LoRAProvider.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all LoRAProviderRoutingTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRAProviderRoutingTests.swift \
        tasks/task-174b-lora-routing-fix.md
git commit -m "Task 174b — Fix: private makeEngine in LoRAProviderRoutingTests maps pro→execute"
```
