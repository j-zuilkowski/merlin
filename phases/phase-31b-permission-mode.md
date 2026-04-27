# Phase 31b — Permission Mode Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 31a complete: failing PermissionModeTests in place.

---

## Write to: Merlin/Engine/PermissionMode.swift

```swift
import SwiftUI

enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case ask
    case autoAccept
    case plan

    var label: String {
        switch self {
        case .ask:        return "ask"
        case .autoAccept: return "auto"
        case .plan:       return "plan"
        }
    }

    var color: Color {
        switch self {
        case .ask:        return .yellow
        case .autoAccept: return .green
        case .plan:       return .blue
        }
    }

    var next: PermissionMode {
        switch self {
        case .ask:        return .autoAccept
        case .autoAccept: return .plan
        case .plan:       return .ask
        }
    }

    static let planSystemPrompt: String = """
    PLAN MODE — You are operating in read-only planning mode.
    You MUST NOT write, create, delete, or move files.
    You MUST NOT run shell commands that modify state.
    You MAY read files, list directories, search files, and inspect the accessibility tree.
    Produce a structured plan with numbered steps. When the user approves, they will switch \
    to Ask mode and submit the plan for execution.
    """
}
```

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add a `permissionMode` property after `var registry: ProviderRegistry?`:

```swift
var permissionMode: PermissionMode = .ask
```

In `buildSystemPrompt()` (or wherever the system message is assembled before sending),
prepend `PermissionMode.planSystemPrompt` when `permissionMode == .plan`:

```swift
private func buildSystemPrompt() -> String {
    var parts: [String] = []
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    // ... existing system prompt content
    return parts.joined(separator: "\n\n")
}
```

In `AuthGate.check(toolCall:)` call site inside the agentic loop, skip the gate for
file-write tools when `permissionMode == .autoAccept`:

```swift
// Before calling authGate.check:
if permissionMode == .autoAccept && isFileWriteTool(call.function.name) {
    // execute directly — no gate
} else {
    let decision = await toolRouter.authGate.check(call)
    // ...
}

private func isFileWriteTool(_ name: String) -> Bool {
    ["write_file", "create_file", "delete_file", "move_file"].contains(name)
}
```

---

## Modify: Merlin/Sessions/LiveSession.swift

Replace the stub `var permissionMode: PermissionMode = .ask` — it already references
the real type after this phase compiles, so no change needed. Confirm `LiveSession`
forwards the mode to its engine:

```swift
var permissionMode: PermissionMode = .ask {
    didSet { appState.engine.permissionMode = permissionMode }
}
```

---

## Modify: Merlin/Views/SessionSidebar.swift

Replace the private `PermissionModeBadge` placeholder with:

```swift
private struct PermissionModeBadge: View {
    let mode: PermissionMode
    var body: some View {
        Text(mode.label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(mode.color.opacity(0.15))
            .foregroundStyle(mode.color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
```

(This replaces the identical placeholder — no visual change, but now backed by the
real type instead of a forward reference.)

---

## Modify: Merlin/Views/ChatView.swift

Add a permission mode badge to the toolbar and ⌘⇧M keyboard shortcut:

In `ChatView` body, inside the toolbar `HStack`, add before the existing provider HUD:

```swift
Button {
    if let session = sessionManager?.activeSession {
        session.permissionMode = session.permissionMode.next
    }
} label: {
    Text(currentMode.label)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(currentMode.color.opacity(0.12))
        .foregroundStyle(currentMode.color)
        .clipShape(RoundedRectangle(cornerRadius: 5))
}
.keyboardShortcut("m", modifiers: [.command, .shift])
.help("Cycle permission mode (⌘⇧M)")
```

`ChatView` needs `@EnvironmentObject private var sessionManager: SessionManager` or
can derive the current mode from `appState.engine.permissionMode` directly.

---

## Modify: project.yml

Add `Merlin/Engine/PermissionMode.swift` to Merlin target sources.

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
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `PermissionModeTests` → 6 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/PermissionMode.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/Views/ChatView.swift \
        project.yml
git commit -m "Phase 31b — PermissionMode (ask/auto/plan) + engine integration"
```
