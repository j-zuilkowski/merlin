# Phase 115b — Critic-Gated Memory Write

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 115a complete: CriticGatedMemoryTests (failing) in place.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add `lastCriticVerdict` property

In the properties block (near `criticOverride`), add:

```swift
// BEFORE (line ~44):
var criticOverride: (any CriticEngineProtocol)?

// AFTER:
var criticOverride: (any CriticEngineProtocol)?
/// Stores the most recent critic verdict from runLoop for test inspection and memory-write gating.
/// Reset to nil at the start of every runLoop invocation.
var lastCriticVerdict: CriticResult?
```

### 2. Reset `lastCriticVerdict` at start of `runLoop`

```swift
// BEFORE (runLoop, just before `var loopCount = 0`):
var loopCount = 0

// AFTER:
lastCriticVerdict = nil
var loopCount = 0
```

### 3. Store verdict in the critic switch

```swift
// BEFORE:
let verdict = await critic.evaluate(
    taskType: taskType,
    output: fullText,
    context: context.messages
)
switch verdict {
case .pass:
    break
case .fail(let reason):
    continuation.yield(.systemNote("[Critic: \(reason)]"))
case .skipped:
    continuation.yield(.systemNote("[unverified — critic unavailable]"))
}

// AFTER:
let verdict = await critic.evaluate(
    taskType: taskType,
    output: fullText,
    context: context.messages
)
lastCriticVerdict = verdict
switch verdict {
case .pass:
    break
case .fail(let reason):
    continuation.yield(.systemNote("[Critic: \(reason)]"))
case .skipped:
    continuation.yield(.systemNote("[unverified — critic unavailable]"))
}
```

### 4. Gate memory write on `lastCriticVerdict`

```swift
// BEFORE:
if let client = xcalibreClient, AppSettings.shared.memoriesEnabled {
    let summary = context.messages
        .filter { $0.role == .assistant }
        .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
        .joined(separator: "\n")
        .prefix(2000)
    if !summary.isEmpty {
        _ = await client.writeMemoryChunk(
            text: String(summary),
            chunkType: "episodic",
            sessionID: sessionStore?.activeSession?.id.uuidString,
            projectPath: currentProjectPath,
            tags: []
        )
    }
}

// AFTER:
if let client = xcalibreClient, AppSettings.shared.memoriesEnabled {
    // Skip memory write when critic explicitly rejected this session's output.
    // nil (critic not invoked) and .pass / .skipped both allow the write.
    if case .fail = lastCriticVerdict {
        // Critic failed — do not pollute the memory store with low-quality output.
    } else {
        let summary = context.messages
            .filter { $0.role == .assistant }
            .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
            .joined(separator: "\n")
            .prefix(2000)
        if !summary.isEmpty {
            _ = await client.writeMemoryChunk(
                text: String(summary),
                chunkType: "episodic",
                sessionID: sessionStore?.activeSession?.id.uuidString,
                projectPath: currentProjectPath,
                tags: []
            )
        }
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'CriticGated.*passed|CriticGated.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; CriticGatedMemoryTests → 7 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 115b — critic-gated memory write (suppress xcalibre write on critic .fail)"
```
