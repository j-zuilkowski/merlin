# Phase 29 — ProjectRef + ProjectPickerView + WindowGroup

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 28b complete: macOS menu (New Session, Stop, Provider switching, Settings).

Introduces multi-window support: one NSWindow per project. `WindowGroup(for: ProjectRef.self)`
routes each project to its own workspace window. At launch with no open windows a
`ProjectPickerView` is shown (recent projects + Open Folder…).

No a/b split — this phase adds only a struct and SwiftUI views with no new testable
business logic. Pure entry-point wiring.

---

## Write to: Merlin/App/ProjectRef.swift

```swift
import Foundation

struct ProjectRef: Codable, Hashable, Identifiable, Sendable {
    // `path` is the canonical identifier — resolved absolute path.
    var path: String
    var displayName: String
    var lastOpenedAt: Date

    var id: String { path }

    static func make(url: URL) -> ProjectRef {
        let resolved = url.resolvingSymlinksInPath()
        return ProjectRef(
            path: resolved.path,
            displayName: resolved.lastPathComponent,
            lastOpenedAt: Date()
        )
    }
}
```

---

## Write to: Merlin/App/RecentProjectsStore.swift

```swift
import Foundation
import Combine

@MainActor
final class RecentProjectsStore: ObservableObject {
    private static let key = "com.merlin.recentProjects"
    private static let maxEntries = 10

    @Published private(set) var projects: [ProjectRef] = []

    init() { load() }

    func touch(_ ref: ProjectRef) {
        var updated = ref
        updated.lastOpenedAt = Date()
        var list = projects.filter { $0.path != ref.path }
        list.insert(updated, at: 0)
        projects = Array(list.prefix(Self.maxEntries))
        save()
    }

    func remove(_ ref: ProjectRef) {
        projects.removeAll { $0.path == ref.path }
        save()
    }

    func clear() {
        projects = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([ProjectRef].self, from: data)
        else { return }
        projects = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
```

---

## Write to: Merlin/Views/ProjectPickerView.swift

```swift
import SwiftUI

struct ProjectPickerView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @Environment(\.openWindow) private var openWindow

    @State private var selected: ProjectRef?
    @State private var isShowingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merlin")
                        .font(.title2.bold())
                    Text("Open a project to start a session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Recent projects
            if recents.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No recent projects")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Projects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(recents.projects) { ref in
                            ProjectRowView(ref: ref, isSelected: selected?.path == ref.path)
                                .onTapGesture { selected = ref }
                                .onTapGesture(count: 2) { open(ref) }
                                .contextMenu {
                                    Button("Remove from Recents") {
                                        if selected?.path == ref.path { selected = nil }
                                        recents.remove(ref)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Clear Recents") { recents.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Folder…") { isShowingFilePicker = true }
                Button("Open") { if let s = selected { open(s) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 380)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                open(.make(url: url))
            }
        }
    }

    private func open(_ ref: ProjectRef) {
        recents.touch(ref)
        openWindow(value: ref)
    }
}

private struct ProjectRowView: View {
    let ref: ProjectRef
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayName)
                    .font(.body.weight(.medium))
                Text(ref.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ref.lastOpenedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
```

---

## Modify: Merlin/App/MerlinApp.swift

Replace the entire file:

```swift
import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var recents = RecentProjectsStore()

    var body: some Scene {
        // Launch picker — shown when no workspace windows are open
        WindowGroup("Merlin", id: "picker") {
            ProjectPickerView()
                .environmentObject(recents)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 380)

        // Per-project workspace window
        WindowGroup(for: ProjectRef.self) { $ref in
            if let ref {
                WorkspaceView(projectRef: ref)
                    .environmentObject(recents)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { MerlinCommands() }

        Settings {
            // Placeholder — wired properly in phase 30b
            Text("Settings")
                .padding()
        }
    }
}
```

---

## Write to: Merlin/Views/WorkspaceView.swift (placeholder)

This placeholder lets the project compile. `WorkspaceView` is fully implemented in phase 30b.

```swift
import SwiftUI

struct WorkspaceView: View {
    let projectRef: ProjectRef

    var body: some View {
        Text("Loading \(projectRef.displayName)…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

---

## Modify: project.yml

Add new source files to the `Merlin` target sources:
- `Merlin/App/ProjectRef.swift`
- `Merlin/App/RecentProjectsStore.swift`
- `Merlin/Views/ProjectPickerView.swift`
- `Merlin/Views/WorkspaceView.swift`

Then regenerate:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme Merlin -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'warning:|error:|BUILD SUCCEEDED|BUILD FAILED' | head -30
```

Expected: `BUILD SUCCEEDED`, zero errors, zero warnings.

Manual check: launching the app shows the project picker. Selecting a recent project
or clicking Open Folder… opens a workspace window titled `<project> — Merlin`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/ProjectRef.swift \
        Merlin/App/RecentProjectsStore.swift \
        Merlin/App/MerlinApp.swift \
        Merlin/Views/ProjectPickerView.swift \
        Merlin/Views/WorkspaceView.swift \
        project.yml
git commit -m "Phase 29 — ProjectRef + ProjectPickerView + multi-window WindowGroup"
```
