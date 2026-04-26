# Phase 01 — Project Scaffold

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Full design in: architecture.md, llm.md

---

## Task
Create all project files, then run `xcodegen generate` to produce `Merlin.xcodeproj`.

---

## Create: project.yml

```yaml
name: Merlin
options:
  bundleIdPrefix: com.merlin
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.4"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    SWIFT_STRICT_CONCURRENCY: complete
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""

targets:
  Merlin:
    type: application
    platform: macOS
    sources: [Merlin/]
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.app
        PRODUCT_NAME: Merlin
        INFOPLIST_FILE: Merlin/Info.plist
        CODE_SIGN_ENTITLEMENTS: Merlin/Merlin.entitlements
        ENABLE_HARDENED_RUNTIME: YES

  TestTargetApp:
    type: application
    platform: macOS
    sources: [TestTargetApp/]
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.TestTargetApp
        PRODUCT_NAME: TestTargetApp
        INFOPLIST_FILE: TestTargetApp/Info.plist

  MerlinTests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinTests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinTests

  MerlinLiveTests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinLiveTests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinLiveTests

  MerlinE2ETests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinE2ETests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinE2ETests

schemes:
  MerlinTests:
    build:
      targets:
        Merlin: all
        MerlinTests: [test]
    test:
      targets: [MerlinTests]

  MerlinTests-Live:
    build:
      targets:
        Merlin: all
        MerlinLiveTests: [test]
        MerlinE2ETests: [test]
        TestTargetApp: all
    test:
      targets: [MerlinLiveTests, MerlinE2ETests]
      environmentVariables:
        RUN_LIVE_TESTS:
          value: "1"
          isEnabled: true
```

---

## Create: Merlin/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.merlin.app</string>
    <key>CFBundleName</key><string>Merlin</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Merlin uses Accessibility to inspect and control UI elements in other apps during development automation.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Merlin captures screenshots of app windows to enable AI-driven visual UI analysis.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Merlin sends Apple Events to Xcode to open files at specific line numbers.</string>
</dict>
</plist>
```

## Create: Merlin/Merlin.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><false/>
    <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
```

## Create: TestTargetApp/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.merlin.TestTargetApp</string>
    <key>CFBundleName</key><string>TestTargetApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

---

## Create: TestHelpers/MockProvider.swift

```swift
import Foundation
@testable import Merlin

final class MockProvider: LLMProvider, @unchecked Sendable {
    var id_: String = "mock"
    var id: String { id_ }
    var baseURL: URL { URL(string: "http://localhost")! }
    var wasUsed = false
    private let chunks: [CompletionChunk]
    private var responses: [MockLLMResponse]
    private var responseIndex = 0

    init(chunks: [CompletionChunk]) { self.chunks = chunks; self.responses = [] }
    init(responses: [MockLLMResponse]) { self.chunks = []; self.responses = responses }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        wasUsed = true
        let toSend: [CompletionChunk]
        if !responses.isEmpty {
            let resp = responses[min(responseIndex, responses.count - 1)]
            responseIndex += 1
            toSend = resp.chunks
        } else { toSend = chunks }
        return AsyncThrowingStream { continuation in
            for chunk in toSend { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

enum MockLLMResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)

    var chunks: [CompletionChunk] {
        switch self {
        case .text(let s):
            return [
                CompletionChunk(delta: .init(content: s), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        case .toolCall(let id, let name, let args):
            return [
                CompletionChunk(delta: .init(toolCalls: [
                    .init(index: 0, id: id, function: .init(name: name, arguments: args))
                ]), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "tool_calls"),
            ]
        }
    }
}
```

## Create: TestHelpers/NullAuthPresenter.swift

```swift
import Foundation
@testable import Merlin

final class NullAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision { .deny }
}

final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false
    init(response: AuthDecision) { self.response = response }
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true; return response
    }
}
```

## Create: TestHelpers/EngineFactory.swift

```swift
import Foundation
@testable import Merlin

@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil) -> AgenticEngine {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    let router = ToolRouter(authGate: gate)
    let ctx = ContextManager()
    let pro = proProvider ?? provider ?? MockProvider(chunks: [])
    let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: LMStudioProvider(),
                         toolRouter: router, contextManager: ctx)
}
```

---

## Create directory structure

Create a `// placeholder` stub for every file in the layout below:

```
Merlin/App/MerlinApp.swift          — use non-stub content below
Merlin/App/AppState.swift
Merlin/Providers/LLMProvider.swift
Merlin/Providers/DeepSeekProvider.swift
Merlin/Providers/LMStudioProvider.swift
Merlin/Providers/SSEParser.swift
Merlin/Engine/AgenticEngine.swift
Merlin/Engine/ContextManager.swift
Merlin/Engine/ToolRouter.swift
Merlin/Engine/ThinkingModeDetector.swift
Merlin/Auth/AuthGate.swift
Merlin/Auth/AuthMemory.swift
Merlin/Auth/PatternMatcher.swift
Merlin/Tools/ToolDefinitions.swift
Merlin/Tools/FileSystemTools.swift
Merlin/Tools/ShellTool.swift
Merlin/Tools/AppControlTools.swift
Merlin/Tools/ToolDiscovery.swift
Merlin/Tools/XcodeTools.swift
Merlin/Tools/AXInspectorTool.swift
Merlin/Tools/ScreenCaptureTool.swift
Merlin/Tools/CGEventTool.swift
Merlin/Tools/VisionQueryTool.swift
Merlin/Sessions/Session.swift
Merlin/Sessions/SessionStore.swift
Merlin/Keychain/KeychainManager.swift
Merlin/Views/ContentView.swift
Merlin/Views/ChatView.swift
Merlin/Views/ToolLogView.swift
Merlin/Views/ScreenPreviewView.swift
Merlin/Views/AuthPopupView.swift
Merlin/Views/ProviderHUD.swift
Merlin/Views/FirstLaunchSetupView.swift
Merlin/App/ToolRegistration.swift
MerlinTests/Unit/SharedTypesTests.swift
MerlinTests/Unit/ProviderTests.swift
MerlinTests/Unit/KeychainTests.swift
MerlinTests/Unit/PatternMatcherTests.swift
MerlinTests/Unit/AuthMemoryTests.swift
MerlinTests/Unit/AuthGateTests.swift
MerlinTests/Unit/ContextManagerTests.swift
MerlinTests/Unit/ThinkingModeDetectorTests.swift
MerlinTests/Unit/SessionSerializationTests.swift
MerlinTests/Unit/ToolRouterTests.swift
MerlinTests/Unit/AgenticEngineTests.swift
MerlinTests/Unit/AppControlTests.swift
MerlinTests/Unit/ToolDiscoveryTests.swift
MerlinTests/Unit/CGEventToolTests.swift
MerlinTests/Integration/FileSystemToolTests.swift
MerlinTests/Integration/ShellToolTests.swift
MerlinTests/Integration/XcodeToolTests.swift
MerlinTests/Integration/AXInspectorTests.swift
MerlinTests/Integration/ScreenCaptureTests.swift
MerlinLiveTests/DeepSeekProviderLiveTests.swift
MerlinLiveTests/LMStudioProviderLiveTests.swift
MerlinE2ETests/AgenticLoopE2ETests.swift
MerlinE2ETests/GUIAutomationE2ETests.swift
MerlinE2ETests/VisualLayoutTests.swift
TestTargetApp/TestTargetAppMain.swift
TestTargetApp/ContentView.swift
```

## Create: Merlin/App/MerlinApp.swift (non-stub)

```swift
import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.showFirstLaunchSetup {
                    FirstLaunchSetupView().environmentObject(appState)
                } else {
                    ContentView().environmentObject(appState)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

---

## Verify

Run these commands in order:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`. Warnings are acceptable, errors are not.
