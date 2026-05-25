# Task 246b — SessionStart Hook

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 246a complete: failing tests for HookEvent.sessionStart and HookEngine.runSessionStart.

---

## Edit

### Existing file: Merlin/Engine/HookEngine.swift

Locate the `HookEvent` enum and add the `sessionStart` case:

```swift
// Add to HookEvent enum:
case sessionStart
```

Add the `runSessionStart` method to `HookEngine`:

```swift
/// Called when a session opens with a project path loaded.
/// Reads pending.json and injects top-3 findings as a system note.
/// Returns the formatted note string, or nil if the queue is empty.
func runSessionStart(projectPath: String) async -> String? {
    let storePath = projectPath + "/.merlin/pending.json"
    let queue = PendingAttentionQueue(storePath: storePath)
    let top = await queue.top(n: 3)
    guard !top.isEmpty else { return nil }

    var lines = ["**Discipline — pending attention (top \(top.count)):**"]
    for f in top {
        let icon: String
        switch f.severity {
        case .block:  icon = "🔴"
        case .nudge:  icon = "🟡"
        case .silent: icon = "⚪"
        }
        lines.append("- \(icon) [\(f.category.rawValue)] \(f.summary)")
        if let action = f.suggestedAction {
            lines.append("  → \(action)")
        }
    }
    let note = lines.joined(separator: "\n")
    TelemetryEmitter.shared.emit("discipline.session-start.injected",
        data: ["findings_count": top.count])
    return note
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 246a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-246b-session-start-hook.md \
    Merlin/Engine/HookEngine.swift
git commit -m "Task 246b — SessionStart hook event + system-reminder injection"
```
