# Phase 68 — Skills Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 67 complete: MCPSettingsView with add/remove server configs.

Add `AppSettings.disabledSkillNames: [String]` (persisted to config.toml).
Replace the stub `SkillsSettingsView` in `SettingsWindowView.swift` with a real view that
lists all loaded skills and lets the user toggle each one enabled/disabled.

---

## Edit: Merlin/Config/AppSettings.swift

Add published property after `maxSubagentDepth`:

```swift
    @Published var disabledSkillNames: [String] = []
```

Add to `ConfigFile` struct:

```swift
        var disabledSkillNames: [String]?
```

Add CodingKey:

```swift
            case disabledSkillNames = "disabled_skill_names"
```

Add to `load(from:)`:

```swift
        if let value = config.disabledSkillNames { disabledSkillNames = value }
```

Add to `save(to:)` after the xcalibre_token block:

```swift
        if !disabledSkillNames.isEmpty {
            let quoted = disabledSkillNames.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("disabled_skill_names = [\(quoted)]")
        }
```

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `SkillsSettingsView` struct with:

```swift
// MARK: - Skills

struct SkillsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var skillsRegistry: SkillsRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if skillsRegistry.skills.isEmpty {
                Text("No skills installed.\nAdd SKILL.md files to ~/.merlin/skills/ or .merlin/skills/ in your project.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(skillsRegistry.skills) { skill in
                    Toggle(isOn: Binding(
                        get: { !settings.disabledSkillNames.contains(skill.name) },
                        set: { enabled in
                            if enabled {
                                settings.disabledSkillNames.removeAll { $0 == skill.name }
                            } else if !settings.disabledSkillNames.contains(skill.name) {
                                settings.disabledSkillNames.append(skill.name)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name).bold()
                            if !skill.frontmatter.description.isEmpty {
                                Text(skill.frontmatter.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(skill.isProjectScoped ? "Project" : "Personal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Text("Disabled skills are hidden from the agent's tool list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
```

Note: `SkillsSettingsView` needs `SkillsRegistry` in the environment. Ensure the Settings scene
in `MerlinApp.swift` injects `.environmentObject(appState.skillsRegistry)` if not already present.
If AppState does not expose a top-level `skillsRegistry`, use a fallback `SkillsRegistry(projectPath: "")`.

Fallback if `SkillsRegistry` is not available in the environment at the Settings scene level — use:

```swift
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")
```

instead of `@EnvironmentObject`, and keep `@ObservedObject private var settings = AppSettings.shared`.

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
git add Merlin/Config/AppSettings.swift \
        Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 68 — SkillsSettingsView: per-skill enable/disable via AppSettings.disabledSkillNames"
```
