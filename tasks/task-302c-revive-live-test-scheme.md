# Task 302c — Revive the MerlinTests-Live Scheme

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

This is a **bug-fix task**, not a feature task — it runs before task 303a.

The `MerlinTests-Live` scheme builds three targets: `MerlinLiveTests`, `MerlinE2ETests`,
`TestTargetApp`. No task Verify command has ever compiled this scheme — every task to
date verified `-scheme MerlinTests`, which builds a different test target. As a result
the live/E2E test targets have bit-rotted against the app target they `@testable import`:

1. **`AgenticEngine.init` changed in task 145b** ("Remove proProvider/flashProvider/
   visionProvider, simplify routing"). The engine no longer takes provider arguments —
   it takes `slotAssignments: [AgentSlot: String]` plus a `ProviderRegistry`. The current
   initializer is:
   ```
   init(slotAssignments: [AgentSlot: String] = [:],
        activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs,
        registry: ProviderRegistry? = nil,
        toolRouter: ToolRouter,
        contextManager: ContextManager,
        xcalibreClient: (any XcalibreClientProtocol)? = nil,
        kagEngine: KAGEngine = .shared,
        memoryBackend: (any MemoryBackendPlugin)? = nil)
   ```
2. **`LMStudioProvider` was deleted** in a later task (the unit test
   `VirtualProviderIDTests.testLMStudioProviderClassIsGone` guards its removal). LM Studio
   is now reached through the generic `OpenAICompatibleProvider` pointed at LM Studio's
   local endpoint (`http://localhost:1234/v1`), or resolved from the provider registry.

Task 303 (the eval harness) lives in `MerlinE2ETests` and verifies against
`MerlinTests-Live`. The scheme must compile before 303 can proceed. This task repairs
the rot. No new surface area is introduced.

## 1. Delete: MerlinLiveTests/LMStudioProviderLiveTests.swift
The entire file (one test, `testVisionQueryRoundTrip`) constructs and exercises the
deleted `LMStudioProvider` class. It is obsolete — a vision live test against LM Studio,
if wanted later, is its own task. Remove the file:
```
git rm MerlinLiveTests/LMStudioProviderLiveTests.swift
```

## 2. Rewrite: MerlinE2ETests/AgenticLoopE2ETests.swift
This file calls the pre-145b `AgenticEngine(proProvider:flashProvider:visionProvider:…)`
initializer (gone) and constructs `LMStudioProvider()` (gone). Replace the whole file
with the version below, which builds a `ProviderRegistry` holding the live
`DeepSeekProvider` and drives the engine through `slotAssignments` — the same pattern
`TestHelpers/EngineFactory.swift` (`EngineFactory.make`) uses with mock providers.

```swift
import Foundation
import XCTest
@testable import Merlin

final class AgenticLoopE2ETests: XCTestCase {
    @MainActor
    func testFullLoopWithRealDeepSeek() async throws {
        try skipUnlessLiveEnvironment()
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? KeychainManager.readAPIKey()
        else {
            throw XCTSkip("No API key")
        }

        let tmpPath = "/tmp/merlin-e2e-test.txt"
        try "hello from e2e test".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "read_file") { args in
            struct PathArgs: Decodable { var path: String }
            let decoded = try JSONDecoder().decode(PathArgs.self, from: Data(args.utf8))
            return try await FileSystemTools.readFile(path: decoded.path)
        }

        // Post-task-145b: AgenticEngine resolves providers from a ProviderRegistry
        // via slot assignments — it no longer takes pro/flash/vision arguments.
        // See TestHelpers/EngineFactory.swift for the same construction with mocks.
        let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
        let config = ProviderConfig(
            id: pro.id,
            displayName: pro.id,
            baseURL: pro.baseURL.absoluteString,
            model: pro.id,
            isEnabled: true,
            isLocal: false,
            supportsThinking: true,
            supportsVision: false,
            kind: .openAICompatible)
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath:
                "/tmp/merlin-e2e-registry-\(UUID().uuidString).json"),
            initialProviders: [config])
        registry.add(pro)
        registry.activeProviderID = pro.id

        let engine = AgenticEngine(
            slotAssignments: [.execute: pro.id, .reason: pro.id, .vision: pro.id],
            registry: registry,
            toolRouter: router,
            contextManager: ContextManager())

        var finalText = ""
        for await event in engine.send(userMessage:
            "Read \(tmpPath) and tell me what it says") {
            if case .text(let text) = event {
                finalText += text
            }
        }

        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"))
    }
}
```

## 3. Edit: MerlinE2ETests/GUIAutomationE2ETests.swift
In `testVisionQueryIdentifiesButton` (line ~60), replace:
```swift
let provider = LMStudioProvider()
```
with an `OpenAICompatibleProvider` pointed at LM Studio's local endpoint:
```swift
let provider = OpenAICompatibleProvider(
    id: "lmstudio",
    baseURL: URL(string: "http://localhost:1234/v1")!,
    apiKey: nil,
    modelID: "")
```
(`modelID: ""` lets LM Studio use its loaded model; if `VisionQueryTool.query` requires
an explicit model id, set it to the loaded vision model.) Change nothing else in the file.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: **BUILD FAILED — but every remaining `error:` line must name `EvalHarness`,
`EvalRun`, or `ToolCallRecord`.** Those symbols belong to task 303b and do not exist
yet; the uncommitted `MerlinE2ETests/EvalHarnessSmokeTests.swift` (task 303a's test
file) references them, so the scheme cannot fully build until 303b lands. That is
correct and expected here.

There must be **no** `LMStudioProvider` error and **no** `AgenticEngine`-initializer
mismatch error left. If any *other* compile error surfaces (further bit-rot in
`VisualLayoutTests.swift`, `DeepSeekProviderLiveTests.swift`, or `TestTargetApp`), it is
the same class of rot: fix it mechanically against the **current app-target API** — the
`Merlin` target is authoritative, the stale test is wrong, not the app. Do not stop on a
bit-rot compile error; fix it, and record what you changed in a `## Fixes` section
appended to this task doc before committing.

## Commit
```
git add MerlinLiveTests/LMStudioProviderLiveTests.swift \
  MerlinE2ETests/AgenticLoopE2ETests.swift \
  MerlinE2ETests/GUIAutomationE2ETests.swift \
  Merlin.xcodeproj/project.pbxproj \
  tasks/task-302c-revive-live-test-scheme.md
git commit -m "Task 302c — Revive the MerlinTests-Live scheme (post-145b rot)"
```
(`git add` of the deleted file stages its removal. Include `project.pbxproj` only if
`xcodegen generate` changed it.)
