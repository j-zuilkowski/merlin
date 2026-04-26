# Phase 19 — AppState + MerlinApp Entry Point

Context: HANDOFF.md. All engine + session components exist.

## Write to: Merlin/App/AppState.swift

```swift
import SwiftUI

// Pending auth request — drives the AuthPopupView sheet
struct AuthRequest {
    var tool: String
    var argument: String
    var reasoningStep: String
    var suggestedPattern: String
    // Internal: continuation to resolve the decision
    var resolve: (AuthDecision) -> Void
}

@MainActor
final class AppState: ObservableObject {
    @Published var engine: AgenticEngine
    @Published var sessionStore: SessionStore
    @Published var authMemory: AuthMemory
    @Published var showFirstLaunchSetup: Bool = false

    // Auth popup — set by AuthPresenter implementation, cleared on resolution
    @Published var showAuthPopup: Bool = false
    @Published var pendingAuthRequest: AuthRequest? = nil

    // Streaming tool log lines (appended during tool execution, cleared each turn start)
    @Published var toolLogLines: [ToolLogLine] = []

    // Last captured screenshot for ScreenPreviewView
    @Published var lastScreenshot: (data: Data, timestamp: Date, sourceBundleID: String)? = nil

    // Current provider being used (for ProviderHUD)
    @Published var activeProviderID: String = "deepseek-v4-pro"
    @Published var thinkingModeActive: Bool = false

    init()  // wires engine, router, authGate, sessionStore together; see below

    // Called by AuthPopupView button actions
    func resolveAuth(_ decision: AuthDecision) {
        pendingAuthRequest?.resolve(decision)
        pendingAuthRequest = nil
        showAuthPopup = false
    }
}

// MARK: - AuthPresenter conformance

extension AppState: AuthPresenter {
    // Called by AuthGate when no remembered pattern matches.
    // Presents the popup and suspends until the user decides.
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        await withCheckedContinuation { continuation in
            self.pendingAuthRequest = AuthRequest(
                tool: tool,
                argument: argument,
                reasoningStep: "",   // AgenticEngine sets this before calling authGate
                suggestedPattern: suggestedPattern,
                resolve: { continuation.resume(returning: $0) }
            )
            self.showAuthPopup = true
        }
    }
}
```

## AppState.init wiring sequence

```
1. authMemory = AuthMemory(storePath: authStorePath)
2. authGate = AuthGate(memory: authMemory, presenter: self)  // self = AppState
3. toolRouter = ToolRouter(authGate: authGate)
4. Register streaming shell handler (see ToolLogView streaming below)
5. registerAllTools(router: toolRouter)                      // phase-19b
6. contextManager = ContextManager()
7. sessionStore = SessionStore()
8. engine = AgenticEngine(proProvider:flashProvider:visionProvider:
                          toolRouter:contextManager:)
9. engine.sessionStore = sessionStore                        // weak ref for save-on-turn
10. if KeychainManager.readAPIKey() == nil { showFirstLaunchSetup = true }
```

## ToolLogView streaming — shell handler override

After `registerAllTools`, override the `run_shell` handler to stream lines into
`AppState.toolLogLines` in real time:

```swift
toolRouter.register(name: "run_shell") { [weak self] args in
    struct A: Decodable { var command: String; var cwd: String?; var timeout_seconds: Int? }
    let a = try JSONDecoder().decode(A.self, from: args.data(using: .utf8)!)
    var stdout = ""; var stderr = ""
    for try await line in ShellTool.stream(command: a.command, cwd: a.cwd,
                                           timeoutSeconds: a.timeout_seconds ?? 120) {
        await MainActor.run {
            self?.toolLogLines.append(ToolLogLine(text: line.text,
                                                  source: line.source == .stdout ? .stdout : .stderr,
                                                  timestamp: Date()))
        }
        if line.source == .stdout { stdout += line.text + "\n" }
        else { stderr += line.text + "\n" }
    }
    return "exit:0\nstdout:\(stdout)\nstderr:\(stderr)"
}
```

This re-registration after `registerAllTools` overwrites the buffering handler
with the streaming one for `run_shell` only.

struct ToolLogLine: Identifiable {
    enum Source { case stdout, stderr, system }
    var id = UUID()
    var text: String
    var source: Source
    var timestamp: Date
}
```

## Write to: Merlin/App/MerlinApp.swift

```swift
import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showFirstLaunchSetup {
                FirstLaunchSetupView()
                    .environmentObject(appState)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

`AppState.init` must:
1. Check `KeychainManager.readAPIKey()` — if nil, set `showFirstLaunchSetup = true`
2. Construct `AuthMemory(storePath: authStorePath)`
3. Construct `AuthGate(memory: authMemory, presenter: ...)` — presenter wired later in phase-22
4. Construct `ToolRouter(authGate: authGate)` and register all tool handlers
5. Construct `AgenticEngine(proProvider:flashProvider:visionProvider:toolRouter:contextManager:)`
6. Construct `SessionStore()` and restore active session into engine context if one exists

## Acceptance
- [ ] `swift build` — zero errors
- [ ] App launches without crash (no UI required yet)
