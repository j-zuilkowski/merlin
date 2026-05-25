# Phase 70 — Permissions Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 69 complete: SearchSettingsView with Brave API key.

Replace the stub `PermissionsSettingsView` in `SettingsWindowView.swift` with a real view that
reads from `AuthMemory` (stored at `~/.merlin/auth.json`) and displays allow/deny patterns
with the ability to remove individual entries.

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `PermissionsSettingsView` struct with:

```swift
// MARK: - Permissions

struct PermissionsSettingsView: View {
    @State private var memory: AuthMemory = AuthMemory(storePath: Self.defaultStorePath)

    private static var defaultStorePath: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return "\(home)/.merlin/auth.json"
    }

    var body: some View {
        VSplitView {
            patternList(
                title: "Always Allow",
                patterns: memory.allowPatterns,
                onRemove: { pattern in
                    memory.removeAllowPattern(tool: pattern.tool, pattern: pattern.pattern)
                    memory.save()
                }
            )

            patternList(
                title: "Always Deny",
                patterns: memory.denyPatterns,
                onRemove: { pattern in
                    memory.removeDenyPattern(tool: pattern.tool, pattern: pattern.pattern)
                    memory.save()
                }
            )
        }
        .onAppear { memory = AuthMemory(storePath: Self.defaultStorePath) }
    }

    @ViewBuilder
    private func patternList(
        title: String,
        patterns: [AuthPattern],
        onRemove: @escaping (AuthPattern) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.top, .horizontal])
            if patterns.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(patterns, id: \.pattern) { pattern in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.tool).bold()
                            Text(pattern.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            onRemove(pattern)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
```

Also ensure `AuthMemory` has a public `save()` method. Check `Merlin/Auth/AuthMemory.swift` —
if `save()` is private or missing, make it `func save()` (public within module):

---

## Edit: Merlin/Auth/AuthMemory.swift

If `save()` is not `internal` or public, change its visibility so `PermissionsSettingsView` can call it.
The method should write the patterns back to `storePath`. If it's already `func save()`, no change needed.

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
git add Merlin/UI/Settings/SettingsWindowView.swift \
        Merlin/Auth/AuthMemory.swift
git commit -m "Phase 70 — PermissionsSettingsView: allow/deny pattern list with remove buttons"
```
