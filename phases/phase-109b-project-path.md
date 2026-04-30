# Phase 109b — Project Path AppSettings Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 109a complete: ProjectPathSettingsTests (failing) in place.

---

## Edit: Merlin/Config/AppSettings.swift — add projectPath

Add to published properties (alongside memoriesEnabled, xcalibreToken):
```swift
@Published var projectPath: String = ""
```

Add to the TOML-keyed struct (the private Codable struct used for parsing):
```swift
var projectPath: String?
// CodingKey: "project_path"
```

Add to the `CodingKeys` enum:
```swift
case projectPath = "project_path"
```

Add to `applyConfig(_:)` (or equivalent loading function):
```swift
if let value = config.projectPath {
    projectPath = value
}
```

Add to `serializedTOML()` (only write when non-empty):
```swift
if !projectPath.isEmpty {
    lines.append("project_path = \(quoted(projectPath))")
}
```

> The test calls `serializedTOML()` and `applyTOML(_:)`. If AppSettings uses
> different method names, expose `serializedTOML() -> String` and
> `applyTOML(_ toml: String)` as thin wrappers or rename to match the test.
> The underlying serialization path is the same one already used by the FSEvents
> watcher — just expose it for testing.

---

## Edit: Merlin/App/AppState.swift — wire projectPath into engine

After the engine is created (near `self.engine = AgenticEngine(...)`), add:
```swift
engine.currentProjectPath = AppSettings.shared.projectPath.isEmpty
    ? nil
    : AppSettings.shared.projectPath
```

Add an `AppSettings.$projectPath` observation to keep the engine in sync when the
user changes the setting at runtime:
```swift
AppSettings.shared.$projectPath
    .dropFirst()
    .sink { [weak self] newPath in
        self?.engine?.currentProjectPath = newPath.isEmpty ? nil : newPath
    }
    .store(in: &cancellables)
```

(AppState already imports Combine for other observations — add to the same `cancellables` set.)

---

## Edit: Merlin/Views/Settings/RoleSlotSettingsView.swift — Library section

Add a new "Library" section after the "Verification Commands" section:

```swift
Section("Library") {
    LabeledContent("Project Path") {
        TextField(
            "e.g. /Users/you/Projects/my-app",
            text: settings.$projectPath
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
        .help("Scopes xcalibre memory search to this project directory. Leave empty to search all memory.")
    }
    LabeledContent("Memory Enabled") {
        Toggle("", isOn: settings.$memoriesEnabled)
            .labelsHidden()
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectPath.*passed|ProjectPath.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; ProjectPathSettingsTests → all pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/AppSettings.swift \
        Merlin/App/AppState.swift \
        Merlin/Views/Settings/RoleSlotSettingsView.swift
git commit -m "Phase 109b — AppSettings.projectPath wired into engine and Settings UI"
```
