# Task 36b — ConstitutionLoader Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 36a complete: failing ConstitutionLoaderTests in place.

---

## Write to: Merlin/Engine/ConstitutionLoader.swift

```swift
import Foundation

enum ConstitutionLoader {

    /// Loads and concatenates constitution.md files for the given project path.
    /// Search order (project-specific first, global last):
    ///   1. <projectPath>/constitution.md
    ///   2. <projectPath>/.merlin/constitution.md
    ///   3. <globalHome>/constitution.md  (pass nil to skip)
    static func load(projectPath: String, globalHome: String? = defaultHome) -> String {
        var candidates: [String] = [
            "\(projectPath)/constitution.md",
            "\(projectPath)/.merlin/constitution.md",
        ]
        if let home = globalHome {
            candidates.append("\(home)/constitution.md")
        }
        let parts = candidates.compactMap { path -> String? in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        return parts.joined(separator: "\n\n")
    }

    /// Returns the content wrapped in a [Project instructions] system-prompt block,
    /// or an empty string if no constitution.md files exist.
    static func systemPromptBlock(projectPath: String, globalHome: String? = defaultHome) -> String {
        let content = load(projectPath: projectPath, globalHome: globalHome)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "[Project instructions]\n\(content)\n[/Project instructions]"
    }

    private static var defaultHome: String? {
        ProcessInfo.processInfo.environment["HOME"]
    }
}
```

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add a `constitutionContent: String` property (set at session creation, not reloaded mid-session):

```swift
var constitutionContent: String = ""
```

In `buildSystemPrompt()`, prepend the constitution.md block:

```swift
private func buildSystemPrompt() -> String {
    var parts: [String] = []
    if !constitutionContent.isEmpty {
        parts.append(constitutionContent)
    }
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    // ... existing system prompt content
    return parts.joined(separator: "\n\n")
}
```

---

## Modify: Merlin/Sessions/LiveSession.swift

Load constitution.md at session creation and inject into the engine:

```swift
init(projectRef: ProjectRef) {
    self.id = UUID()
    self.title = "New Session"
    self.createdAt = Date()
    self.appState = AppState(projectPath: projectRef.path)

    // Load constitution.md for this project
    let block = ConstitutionLoader.systemPromptBlock(projectPath: projectRef.path)
    self.appState.engine.constitutionContent = block

    // Wire staging buffer
    self.appState.engine.toolRouter.stagingBuffer = stagingBuffer
    self.appState.engine.toolRouter.permissionMode = .ask
}
```

---

## Modify: project.yml

Add `Merlin/Engine/ConstitutionLoader.swift` to Merlin target sources.

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

Expected: `BUILD SUCCEEDED`; `ConstitutionLoaderTests` → 8 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ConstitutionLoader.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift \
        project.yml
git commit -m "Task 36b — ConstitutionLoader + engine integration"
```
