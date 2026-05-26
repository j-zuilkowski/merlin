# Task 192b — KAGEngine AgenticEngine Wiring

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

Task 192a complete: failing tests in `AgenticEngineKAGWiringTests` — they reference
`kag.pendingTask` (private) and `makeEngine(provider:kagEngine:)` (non-existent).

This task makes the tests pass with three targeted changes:
1. `KAGEngine.pendingTask`: `private` → `private(set)` for `@testable` observation
2. `AgenticEngine`: add `kagEngine: KAGEngine` injectable property + call site
3. `TestHelpers/EngineFactory.swift`: add `kagEngine` parameter to `makeEngine`

Version bump: 1.7.0 → 1.8.0 (new capability: KAG extraction is now live end-to-end).

---

## Edit: Merlin/KAG/KAGEngine.swift

Change `private var pendingTask` to `private(set) var pendingTask`:

```diff
-    private var pendingTask: Task<Void, Never>?
+    private(set) var pendingTask: Task<Void, Never>?
```

No other changes to this file.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add stored property (near other private stored properties, around line 110)

```swift
/// KAGEngine used for triple extraction after each turn. Defaults to the
/// process-wide singleton; injectable for testing.
private let kagEngine: KAGEngine
```

### 2. Update `init` to accept `kagEngine` parameter

```diff
 init(slotAssignments: [AgentSlot: String] = [:],
      registry: ProviderRegistry? = nil,
      toolRouter: ToolRouter,
      contextManager: ContextManager,
      xcalibreClient: (any XcalibreClientProtocol)? = nil,
+     kagEngine: KAGEngine = .shared,
      memoryBackend: (any MemoryBackendPlugin)? = nil) {
     self.slotAssignments = slotAssignments
     self.registry = registry
     self.toolRouter = toolRouter
     self.contextManager = contextManager
     self.xcalibreClient = xcalibreClient
+    self.kagEngine = kagEngine
     if let memoryBackend {
         self.memoryBackend = memoryBackend
     }
 }
```

### 3. Insert the schedule call after the telemetry emit at the end of the turn (around line 1173)

Find the block that reads:
```swift
        TelemetryEmitter.shared.emit("engine.turn.complete", durationMs: turnMs, data: [
            "turn": turn,
            "slot": workingSlot.rawValue,
            "provider_id": selectProvider(for: userMessage).id,
            "total_duration_ms": turnMs,
            "tool_call_count": totalToolCallCount,
            "loop_count": loopCount
        ])

        // Fix 2: Reset near-ceiling addendum so it doesn't bleed into the next turn.
        nearCeilingWarningAddendum = nil
```

Insert immediately **after** the `TelemetryEmitter` emit block and **before** the
`nearCeilingWarningAddendum = nil` line:

```swift
        // KAG: schedule triple extraction from the completed assistant response.
        if AppSettings.shared.kagEnabled, !lastResponseText.isEmpty {
            kagEngine.scheduleExtraction(from: lastResponseText, domain: domain.id)
        }
```

---

## Edit: TestHelpers/EngineFactory.swift

Add `kagEngine` parameter to `makeEngine` (default `KAGEngine.shared` so existing
call sites need no changes):

```diff
 @MainActor
 func makeEngine(provider: MockProvider? = nil,
                 proProvider: MockProvider? = nil,
                 flashProvider: MockProvider? = nil,
+                kagEngine: KAGEngine = .shared,
                 xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
```

And thread it through to `AgenticEngine.init`:

```diff
     return AgenticEngine(
         slotAssignments: [.execute: flash.id, .reason: pro.id, .vision: vision.id],
         registry: registry,
         toolRouter: router,
         contextManager: ctx,
+        kagEngine: kagEngine,
         xcalibreClient: xcalibreClient
     )
```

---

## Edit: project.yml — version bump 1.7.0 → 1.8.0

```diff
-    MARKETING_VERSION: "1.7.0"
+    MARKETING_VERSION: "1.8.0"
```

Update `CURRENT_PROJECT_VERSION` (build number) by incrementing by 1 as well
(e.g. if currently 7, set to 8).

After editing `project.yml`:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected:
- `AgenticEngineKAGWiringTests` — 3 tests passed
- All prior tests still pass
- Zero warnings, zero errors

## Commit, tag, push

```bash
cd ~/Documents/localProject/merlin
git add Merlin/KAG/KAGEngine.swift \
        Merlin/Engine/AgenticEngine.swift \
        TestHelpers/EngineFactory.swift \
        project.yml \
        Merlin.xcodeproj/project.pbxproj \
        tasks/task-192a-kag-engine-wiring-tests.md \
        tasks/task-192b-kag-engine-wiring.md
git commit -m "Task 192b — Wire KAGEngine.scheduleExtraction into AgenticEngine; v1.8.0"
git tag v1.8.0
git push origin main --tags
gh release create v1.8.0 \
    --repo j-zuilkowski/merlin \
    --title "v1.8.0 — KAG extraction live end-to-end" \
    --notes "Task 192: KAGEngine.scheduleExtraction is now called after every assistant turn when kagEnabled=true. Triple extraction fires after a 2-second idle delay and writes to the configured backend (LocalKAGPlugin or XcalibreKAGPlugin)." \
    --latest
```
