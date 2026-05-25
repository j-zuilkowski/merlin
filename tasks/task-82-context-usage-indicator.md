# Phase 82 — ContextUsageTracker: Wire Into ProviderHUD

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 81 complete: Scheduler in Settings.

`ContextUsageTracker` exists but is never shown. Wire it into `AppState` (instantiate with
`engine.contextManager`'s window size) and display it as a thin progress bar + label inside
`ProviderHUD`. Update `usedTokens` after each `AgenticEngine.send` turn completes.

---

## Edit: Merlin/App/AppState.swift

Add a `@Published` property:

```swift
    @Published var contextUsage: ContextUsageTracker = ContextUsageTracker(contextWindowSize: 200_000)
```

After `engine` is created in `init`, update the window size from settings:

```swift
        contextUsage = ContextUsageTracker(contextWindowSize: AppSettings.shared.maxTokens)
```

After each tool/message cycle in the engine, update `usedTokens`. The simplest hook is to
observe `ContextManager.messages` count × average token estimate, or — better — add a
`func reportUsage(_ tokens: Int)` to `AgenticEngine` that calls back to AppState.

Add to `AppState`:

```swift
    func updateContextUsage(_ tokens: Int) {
        contextUsage.update(usedTokens: tokens)
    }
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

Add an optional callback property:

```swift
    var onUsageUpdate: ((Int) -> Void)?
```

After each completed turn (at the end of `send(userMessage:)`), call it with the approximate
token count from the context manager. Find where messages are assembled and add:

```swift
        let approxTokens = contextManager.messages.reduce(0) { sum, msg in
            switch msg.content {
            case .text(let t): return sum + t.count / 4
            case .parts(let parts):
                return sum + parts.reduce(0) { s, p in
                    if case .text(let t) = p { return s + t.count / 4 }
                    return s
                }
            }
        }
        onUsageUpdate?(approxTokens)
```

---

## Edit: Merlin/Sessions/LiveSession.swift

Wire the callback in `init`:

```swift
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
        }
```

---

## Edit: Merlin/Views/ProviderHUD.swift

Add a usage bar below the existing HUD content. Read from `@EnvironmentObject var appState: AppState`:

```swift
import SwiftUI

struct ProviderHUD: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                // existing provider name + state indicator content
                providerLabel
                stateIndicator
            }

            if appState.contextUsage.usedTokens > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(usageColor)
                            .frame(
                                width: geo.size.width * min(appState.contextUsage.percentUsed, 1.0),
                                height: 3
                            )
                    }
                }
                .frame(height: 3)
                .help(appState.contextUsage.statusString)
            }
        }
    }

    private var usageColor: Color {
        switch appState.contextUsage.percentUsed {
        case ..<0.6: return .accentColor
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    // Move existing provider label and state indicator into computed vars to keep body clean.
    // Check existing ProviderHUD.swift for current implementation and refactor accordingly.
    private var providerLabel: some View { EmptyView() }
    private var stateIndicator: some View { EmptyView() }
}
```

Read the current `ProviderHUD.swift` body and integrate the usage bar into the existing layout
without breaking the existing HUD content. The bar should appear below the provider name text,
spanning the full width of the HUD.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/AppState.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/Views/ProviderHUD.swift
git commit -m "Phase 82 — ContextUsageTracker wired into AppState + shown as progress bar in ProviderHUD"
```
