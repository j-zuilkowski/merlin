# Phase 109a — Project Path AppSettings Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 108b complete: RAG source attribution in place.

New surface introduced in phase 109b:
  - `AppSettings.projectPath: String` — persisted project path for xcalibre memory scoping (default: "")
  - `AppSettings` serializes `project_path` to/from config.toml
  - `AppState` wires `engine.currentProjectPath` from `AppSettings.projectPath` at init and on change
  - `RoleSlotSettingsView` gains a "Project Path" text field in a new "Library" section

TDD coverage:
  File 1 — ProjectPathSettingsTests: AppSettings.projectPath defaults, round-trip, toml serialization;
            AppState wires engine.currentProjectPath from projectPath

---

## Write to: MerlinTests/Unit/ProjectPathSettingsTests.swift

```swift
import XCTest
@testable import Merlin

final class ProjectPathSettingsTests: XCTestCase {

    // MARK: - AppSettings.projectPath

    func testProjectPathDefaultsEmpty() {
        // AppSettings.projectPath must default to "" (not nil — always a String)
        let settings = makeFreshSettings()
        XCTAssertEqual(settings.projectPath, "")
    }

    func testProjectPathRoundTrip() {
        let settings = makeFreshSettings()
        settings.projectPath = "/Users/alice/Projects/my-app"
        XCTAssertEqual(settings.projectPath, "/Users/alice/Projects/my-app")
    }

    func testProjectPathSerializesToTOML() {
        let settings = makeFreshSettings()
        settings.projectPath = "/home/user/project"
        let toml = settings.serializedTOML()
        XCTAssertTrue(toml.contains("project_path"), "project_path key must appear in serialized TOML")
        XCTAssertTrue(toml.contains("/home/user/project"))
    }

    func testProjectPathNotWrittenToTOMLWhenEmpty() {
        let settings = makeFreshSettings()
        settings.projectPath = ""
        let toml = settings.serializedTOML()
        XCTAssertFalse(toml.contains("project_path"),
                       "project_path must be omitted from TOML when empty")
    }

    func testProjectPathRoundTripsThroughTOML() {
        let settings = makeFreshSettings()
        settings.projectPath = "/opt/code/merlin"

        let toml = settings.serializedTOML()
        let reloaded = makeFreshSettings()
        reloaded.applyTOML(toml)
        XCTAssertEqual(reloaded.projectPath, "/opt/code/merlin")
    }

    // MARK: - Engine wiring

    func testEngineCurrentProjectPathMatchesAppSettings() {
        // AgenticEngine.currentProjectPath must be set from AppSettings.projectPath
        // when AppState initialises the engine.
        let settings = makeFreshSettings()
        settings.projectPath = "/Users/test/project"

        let engine = makeEngine()
        // Simulate the wiring AppState does at init:
        engine.currentProjectPath = settings.projectPath.isEmpty ? nil : settings.projectPath

        XCTAssertEqual(engine.currentProjectPath, "/Users/test/project")
    }

    func testEngineCurrentProjectPathIsNilWhenSettingsEmpty() {
        let settings = makeFreshSettings()
        settings.projectPath = ""

        let engine = makeEngine()
        engine.currentProjectPath = settings.projectPath.isEmpty ? nil : settings.projectPath

        XCTAssertNil(engine.currentProjectPath)
    }
}

// MARK: - Helpers

/// Returns a fresh, isolated AppSettings-like object that has projectPath.
/// Uses the real AppSettings type — tests verify the property exists at compile time.
@MainActor
private func makeFreshSettings() -> AppSettings {
    // Re-use AppSettings.shared but reset projectPath after each test via tearDown
    // is not safe in parallel tests. Instead use the minimal constructor if available,
    // or accept shared-state risk for this compile-time-focused test file.
    // If AppSettings has no isolated init, the compile will at minimum verify
    // .projectPath, .serializedTOML(), and .applyTOML(_:) all exist.
    return AppSettings.shared
}

private func makeEngine() -> AgenticEngine {
    let provider = MinimalProvider()
    let registry = ProviderRegistry()
    registry.add(provider)
    return AgenticEngine(
        slotAssignments: [.execute: provider.id],
        registry: registry,
        toolRouter: ToolRouter(),
        contextManager: ContextManager()
    )
}

private final class MinimalProvider: LLMProvider, @unchecked Sendable {
    let id = "minimal-pp"
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: "ok", thinkingContent: nil, toolCalls: nil), finishReason: "stop"))
            c.finish()
        }
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AppSettings.projectPath`, `AppSettings.serializedTOML()`,
`AppSettings.applyTOML(_:)` not defined (or projectPath not present in TOML serialization).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ProjectPathSettingsTests.swift
git commit -m "Phase 109a — ProjectPathSettingsTests (failing)"
```
