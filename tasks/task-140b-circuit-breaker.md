# Phase 140b — Reasoning-Layer Circuit Breaker Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 140a complete: failing tests for reasoning-layer circuit breaker in place.

Addresses the "safe halt conditions" mitigation from:
"Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems" — VentureBeat
https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems

---

## Edit: Merlin/Config/AppSettings.swift

Add alongside the existing RAG settings (`ragChunkLimit`, `ragRerank`):

```swift
/// TOML key: `agent_circuit_breaker_threshold`.
/// Number of consecutive critic .fail verdicts before the circuit breaker activates.
/// In "halt" mode the next turn is stopped cleanly and the user is directed to act.
/// In "warn" mode a systemNote is emitted but the turn continues.
/// Set to 0 to disable entirely. Default: 3.
///
/// Addresses the "safe halt conditions" mitigation in:
/// "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"
/// https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems
@Published var agentCircuitBreakerThreshold: Int = 3

/// TOML key: `agent_circuit_breaker_mode`.
/// "halt" — stop the next turn cleanly, emit a labelled failure note, require a new
///           session to continue. Recommended: a graceful halt is safer than fluent error.
/// "warn" — emit a systemNote warning but allow the turn to complete.
/// Default: "halt".
@Published var agentCircuitBreakerMode: String = "halt"
```

Add to the TOML CodingKeys enum:
```swift
case agentCircuitBreakerThreshold = "agent_circuit_breaker_threshold"
case agentCircuitBreakerMode = "agent_circuit_breaker_mode"
```

Add to load method:
```swift
if let value = config.agentCircuitBreakerThreshold { agentCircuitBreakerThreshold = value }
if let value = config.agentCircuitBreakerMode { agentCircuitBreakerMode = value }
```

Add to save method (non-default values only):
```swift
if agentCircuitBreakerThreshold != 3 {
    lines.append("agent_circuit_breaker_threshold = \(agentCircuitBreakerThreshold)")
}
if agentCircuitBreakerMode != "halt" {
    lines.append("agent_circuit_breaker_mode = \"\(agentCircuitBreakerMode)\"")
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1 — Add counter property (alongside lastCriticVerdict)

```swift
/// Counts consecutive turns where the critic returned .fail.
/// Reset to 0 on .pass or .skipped. Reset to 0 by AppState.newSession().
/// Used by the reasoning-layer circuit breaker to surface sustained quality
/// degradation rather than letting it accumulate silently.
///
/// Addresses the "silent partial failure" pattern in:
/// "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"
/// https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems
var consecutiveCriticFailures: Int = 0
```

### 2 — Halt check at START of runLoop (before any processing)

Insert immediately after the opening of `runLoop`, before `lastCriticVerdict = nil`:

```swift
// Reasoning-layer circuit breaker — halt mode.
// If the circuit is tripped (consecutiveCriticFailures >= threshold) and the mode is
// "halt", stop this turn cleanly before generating any output. The user is directed
// to start a new session (which resets the counter) or adjust their model settings.
let cbThreshold = await MainActor.run { AppSettings.shared.agentCircuitBreakerThreshold }
let cbMode = await MainActor.run { AppSettings.shared.agentCircuitBreakerMode }
if cbThreshold > 0, consecutiveCriticFailures >= cbThreshold, cbMode == "halt" {
    continuation.yield(.systemNote(
        "🛑 Halted after \(consecutiveCriticFailures) consecutive reliability failures. " +
        "Start a new session or adjust Settings → Providers before continuing."
    ))
    return
}
```

### 3 — Update counter after critic verdict

After `lastCriticVerdict = verdict` is assigned, add:

```swift
switch verdict {
case .pass, .skipped:
    consecutiveCriticFailures = 0
case .fail:
    consecutiveCriticFailures += 1
}
```

### 4 — Warn mode: emit note at END of runLoop

At the end of `runLoop` (after the episodic memory write, before `onUsageUpdate`):

```swift
// Reasoning-layer circuit breaker — warn mode.
// Emit a warning systemNote when at or above threshold in "warn" mode.
// In "halt" mode the check at the top of the next runLoop handles stopping.
if cbThreshold > 0, consecutiveCriticFailures >= cbThreshold, cbMode == "warn" {
    continuation.yield(.systemNote(
        "⚠️ Reliability check failed \(consecutiveCriticFailures) time\(consecutiveCriticFailures == 1 ? "" : "s") consecutively. " +
        "Output quality may be degraded. Check Settings → Providers for suggestions."
    ))
}
```

Note: `cbThreshold` and `cbMode` were read at the top of `runLoop` — reuse those values
here rather than re-reading AppSettings.

---

## Edit: Merlin/App/AppState.swift — reset counter on new session

In `newSession()`, after `engine.contextManager.clear()`, add:

```swift
// Reset the circuit breaker counter so a new session always starts clean.
engine.consecutiveCriticFailures = 0
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 140a tests pass, zero warnings.

## Commit
```bash
git add Merlin/Config/AppSettings.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/App/AppState.swift
git commit -m "Phase 140b — circuit breaker: halt/warn modes, counter reset on new session"
```
