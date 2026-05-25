# Phase 182b — Session Restore Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 182a complete: SessionRestoreTests committed (failing).

---

## Edit: Merlin/Engine/ContextManager.swift

Add `load(_ messages: [Message])` after the `clear()` method.

**Find:**
```swift
    func clear() {
        messages.removeAll()
        estimatedTokens = 0
    }
```

**Replace with:**
```swift
    func clear() {
        messages.removeAll()
        estimatedTokens = 0
    }

    /// Bulk-loads historical messages (e.g. from a restored Session) and
    /// compacts immediately if the injected history exceeds the pre-run threshold.
    func load(_ messages: [Message]) {
        guard !messages.isEmpty else { return }
        for message in messages {
            self.messages.append(message)
        }
        estimatedTokens = recomputeEstimatedTokens()
        compactIfNeededBeforeRun(isContinuation: false)
    }
```

---

## Edit: Merlin/Sessions/LiveSession.swift

Add `initialMessages` and `sessionStore` parameters to `init`. Full replacement:

```swift
// LiveSession — wires all per-session subsystems around an AppState.
//
// Created by SessionManager for each project window session. Responsibilities:
//   • Initialises AppState with the correct project path and constitution.md content
//   • Starts MCPBridge (launches MCP servers, registers their tools)
//   • Starts ThreadAutomationEngine for cron-based automations
//   • Starts MemoryEngine idle timer (generates summaries on inactivity)
//
// permissionMode.didSet propagates the new mode to both AgenticEngine
// and ToolRouter so they stay in sync.
//
// initialMessages: pre-loads a prior session's history into the ContextManager.
// sessionStore: when provided, replaces the AppState-owned store so all live
//   sessions for a project share one store instance.
//
// See: Developer Manual § "Session & State Management → LiveSession"
import Foundation
import SwiftUI

@MainActor
final class LiveSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let appState: AppState
    let skillsRegistry: SkillsRegistry
    private let mcpBridge = MCPBridge()
    private let stagingBufferStorage = StagingBuffer()
    private let memoryEngine = MemoryEngine()
    private let automationStore = ThreadAutomationStore()
    private let automationEngine = ThreadAutomationEngine()
    var permissionMode: PermissionMode = AppSettings.shared.defaultPermissionMode {
        didSet {
            appState.engine.permissionMode = permissionMode
            appState.engine.toolRouter.permissionMode = permissionMode
        }
    }
    let createdAt: Date

    init(projectRef: ProjectRef,
         initialMessages: [Message] = [],
         sessionStore: SessionStore? = nil) {
        self.id = UUID()
        self.title = "New Session"
        self.createdAt = Date()
        self.appState = AppState(projectPath: projectRef.path)
        self.skillsRegistry = SkillsRegistry(projectPath: projectRef.path)
        self.appState.engine.skillsRegistry = self.skillsRegistry
        self.appState.engine.constitutionContent = ConstitutionLoader.systemPromptBlock(projectPath: projectRef.path)
        self.appState.engine.memoriesContent = ConstitutionLoader.defaultMemoriesBlock()
        self.appState.engine.standingInstructions = AppSettings.shared.standingInstructions
        appState.engine.permissionMode = permissionMode
        appState.engine.toolRouter.stagingBuffer = stagingBufferStorage
        appState.engine.toolRouter.permissionMode = permissionMode
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
        }

        // Replace per-AppState store with the shared project-level store if provided.
        if let sessionStore {
            appState.sessionStore = sessionStore
            appState.engine.sessionStore = sessionStore
        }

        // Inject historical messages from a restored session.
        if !initialMessages.isEmpty {
            appState.engine.contextManager.load(initialMessages)
        }

        Task { @MainActor [mcpBridge, projectPath = projectRef.path] in
            let config = MCPConfig.merged(projectPath: projectPath)
            try? await mcpBridge.start(config: config,
                                       toolRouter: appState.engine.toolRouter)
        }

        Task {
            let store = automationStore
            let engine = automationEngine
            let agenticEngine = appState.engine
            await engine.setOnFire { @Sendable [weak agenticEngine] _, prompt in
                Task { @MainActor in
                    guard let engine = agenticEngine else { return }
                    for await _ in engine.send(userMessage: prompt) {}
                }
            }
            await engine.start(store: store)
        }

        // File-based message injection: poll ~/.merlin/inject.txt every 2 seconds.
        // When the file exists, post merlinInjectMessage so the active ChatView
        // submits it as a real user message (visible in the UI with full response).
        // Usage from shell: echo "your prompt" > ~/.merlin/inject.txt
        Task { @MainActor in
            let injectURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.merlin/inject.txt")
            while true {
                if let data = try? Data(contentsOf: injectURL),
                   let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    try? FileManager.default.removeItem(at: injectURL)
                    NotificationCenter.default.post(
                        name: .merlinInjectMessage,
                        object: nil,
                        userInfo: ["message": text]
                    )
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }

        Task {
            let memoryProvider = appState.engine.provider(for: .reason) ?? NullProvider()
            await self.memoryEngine.setProvider(memoryProvider)
            if AppSettings.shared.memoriesEnabled {
                let timeout = AppSettings.shared.memoryIdleTimeout
                let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
                let pendingDir = URL(fileURLWithPath: "\(home)/.merlin/memories/pending")
                let notificationEngine = NotificationEngine()
                await self.memoryEngine.setOnIdleFired { [weak appState] in
                    guard let appState else { return }
                    Task {
                        let messages = await appState.engine.contextManager.messages
                        try? await self.memoryEngine.generateAndNotify(
                            messages: messages,
                            pendingDir: pendingDir,
                            notificationEngine: notificationEngine
                        )
                    }
                }
                await self.memoryEngine.startIdleTimer(timeout: timeout)
            }
        }
    }

    var stagingBuffer: StagingBuffer {
        appState.engine.toolRouter.stagingBuffer ?? stagingBufferStorage
    }
}
```

---

## Edit: Merlin/Sessions/SessionManager.swift

Add `sessionStore` property, pass it to `LiveSession`, add `restore(session:)`. Full replacement:

```swift
import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    let projectRef: ProjectRef
    let sessionStore: SessionStore
    @Published private(set) var liveSessions: [LiveSession] = []
    @Published private(set) var activeSessionID: UUID?

    var activeSession: LiveSession? {
        liveSessions.first { $0.id == activeSessionID }
    }

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
        self.sessionStore = SessionStore(projectPath: projectRef.path)
    }

    @discardableResult
    func newSession(mode: PermissionMode = AppSettings.shared.defaultPermissionMode) async -> LiveSession {
        let session = LiveSession(projectRef: projectRef, sessionStore: sessionStore)
        session.permissionMode = mode
        liveSessions.append(session)
        activeSessionID = session.id
        return session
    }

    /// Restores a persisted Session as a new LiveSession.
    /// The session's message history is injected into the ContextManager and
    /// compacted if it exceeds the pre-run threshold.
    /// The restored LiveSession gets a fresh UUID — the original Session record
    /// on disk is not modified until the user sends a new message.
    @discardableResult
    func restore(session: Session) async -> LiveSession {
        let live = LiveSession(
            projectRef: projectRef,
            initialMessages: session.messages,
            sessionStore: sessionStore
        )
        live.title = session.title
        liveSessions.append(live)
        activeSessionID = live.id
        return live
    }

    func switchSession(to id: UUID) {
        guard liveSessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    func closeSession(_ id: UUID) async {
        liveSessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = liveSessions.last?.id
        }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SessionRestore.*passed|SessionRestore.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; all SessionRestoreTests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-182b-session-restore.md \
        Merlin/Engine/ContextManager.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/Sessions/SessionManager.swift
git commit -m "Phase 182b — ContextManager.load + LiveSession initial messages + SessionManager.restore"
```
