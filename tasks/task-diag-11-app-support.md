# Task diag-11 — App Support Files

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

Covers three small support files that enable system integration and keyboard-shortcut
propagation. No dedicated tests — these are plumbing that other features rely on.

---

## Files

### Merlin/App/AppFocusedValues.swift

`FocusedValues` extensions for propagating engine state to `MerlinCommands`.
SwiftUI `Commands` structs cannot observe `@EnvironmentObject` directly; they use
`@FocusedObject` / `@FocusedValue` instead.

```swift
import SwiftUI

private struct IsEngineRunningKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ActiveProviderIDKey: FocusedValueKey {
    typealias Value = Binding<String>
}

extension FocusedValues {
    var isEngineRunning: Binding<Bool>? {
        get { self[IsEngineRunningKey.self] }
        set { self[IsEngineRunningKey.self] = newValue }
    }
    var activeProviderID: Binding<String>? {
        get { self[ActiveProviderIDKey.self] }
        set { self[ActiveProviderIDKey.self] = newValue }
    }
}
```

**Usage:** Views set `.focusedValue(\.isEngineRunning, $appState.isRunning)`.
`MerlinCommands` reads `@FocusedValue(\.isEngineRunning) var isRunning`.

---

### Merlin/Support/AppIntentsSupport.swift

Minimal App Intents registration required to avoid an Xcode warning about missing
`AppIntent` implementations. `MerlinMetadataIntent` is a stub — Siri integration
is deferred to a future task.

```swift
import AppIntents

struct MerlinMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "Merlin Metadata"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
```

---

### Merlin/Engine/ContextUsageTracker.swift

Tracks token budget usage for the context window progress indicator in ChatView.
Created by `AppState` with the active provider's reported context window size.
Updated after each turn by `AgenticEngine` with the estimated token count.

```swift
import Foundation

@MainActor
final class ContextUsageTracker: ObservableObject {
    let contextWindowSize: Int
    @Published private(set) var usedTokens: Int = 0

    init(contextWindowSize: Int) {
        self.contextWindowSize = contextWindowSize
    }

    func update(usedTokens: Int) {
        self.usedTokens = usedTokens
    }

    var percentUsed: Double {
        guard contextWindowSize > 0 else { return 0 }
        return Double(usedTokens) / Double(contextWindowSize)
    }

    var statusString: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        let used  = fmt.string(from: NSNumber(value: usedTokens)) ?? "\(usedTokens)"
        let total = fmt.string(from: NSNumber(value: contextWindowSize)) ?? "\(contextWindowSize)"
        return "Context: \(used) / \(total) tokens (\(Int(percentUsed * 100))%)"
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD SUCCEEDED (all three files already exist).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/AppFocusedValues.swift \
        Merlin/Support/AppIntentsSupport.swift \
        Merlin/Engine/ContextUsageTracker.swift \
        tasks/task-diag-11-app-support.md
git commit -m "Task diag-11 — AppFocusedValues + AppIntentsSupport + ContextUsageTracker"
```
