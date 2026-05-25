# Phase 19 — AppState + MerlinApp Entry Point

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All engine + session components exist (phases 13b–18). ToolRegistration will be written in phase 19b.

---

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

    init()

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
                reasoningStep: "",
                suggestedPattern: suggestedPattern,
                resolve: { continuation.resume(returning: $0) }
            )
            self.showAuthPopup = true
        }
    }
}
```

## AppState.init wiring sequence

Implement `AppState.init` in this exact order:

```
1. authMemory = AuthMemory(storePath: authStorePath)
   // authStorePath = ~/Library/Application Support/Merlin/auth.json
2. let gate = AuthGate(memory: authMemory, presenter: self)
3. let toolRouter = ToolRouter(authGate: gate)
4. registerAllTools(router: toolRouter)          // phase 19b
5. Override run_shell handler for streaming:
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
6. let ctx = ContextManager()
7. sessionStore = SessionStore()
8. let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-pro")
   let flash = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
   let vision = LMStudioProvider()
   // key = KeychainManager.readAPIKey() ?? ""
9. engine = AgenticEngine(proProvider: pro, flashProvider: flash, visionProvider: vision,
                          toolRouter: toolRouter, contextManager: ctx)
10. engine.sessionStore = sessionStore
11. if KeychainManager.readAPIKey() == nil { showFirstLaunchSetup = true }
```

## ToolLogLine type

Define `ToolLogLine` in AppState.swift (or a separate file if preferred):

```swift
struct ToolLogLine: Identifiable {
    enum Source { case stdout, stderr, system }
    var id = UUID()
    var text: String
    var source: Source
    var timestamp: Date
}
```

---

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

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`. Zero errors.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/AppState.swift Merlin/App/MerlinApp.swift
git commit -m "Phase 19 — AppState wiring + MerlinApp entry point"
```
