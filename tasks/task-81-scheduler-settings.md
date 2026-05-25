# Phase 81 — Scheduler Settings Section + SchedulerEngine Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 80b complete: disabledSkillNames enforced.

`SchedulerEngine` and `SchedulerView` exist but are unreachable. Fix by:
1. Adding `SchedulerEngine` as a singleton (or app-level object) and injecting it via environment
2. Adding a `scheduler` case to `SettingsSection`
3. Adding a `SchedulerSettingsView` that embeds `SchedulerView`

---

## Edit: Merlin/App/MerlinApp.swift

Add `@StateObject private var scheduler = SchedulerEngine()` at the top of `MerlinApp` and
inject it into the environment for all scenes:

```swift
@main
struct MerlinApp: App {
    @StateObject private var recents = RecentProjectsStore()
    @StateObject private var scheduler = SchedulerEngine()

    var body: some Scene {
        WindowGroup("Merlin", id: "picker") {
            ProjectPickerView()
                .environmentObject(recents)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 380)

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
            SettingsWindowView()
                .environmentObject(scheduler)
        }
    }
}
```

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Add `case scheduler` to `SettingsSection`:

```swift
    case scheduler
```

Add label and icon:

```swift
        case .scheduler: return "Scheduler"
        // icon:
        case .scheduler: return "clock"
```

Add to `detailView(for:)`:

```swift
        case .scheduler:
            SchedulerSettingsView()
```

Add the view struct (using `@EnvironmentObject` since SchedulerEngine is now injected):

```swift
// MARK: - Scheduler

private struct SchedulerSettingsView: View {
    @EnvironmentObject private var scheduler: SchedulerEngine

    var body: some View {
        SchedulerView()
            .environmentObject(scheduler)
    }
}
```

Insert `scheduler` in the `CaseIterable` order between `hooks` and `memories`.

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
git add Merlin/App/MerlinApp.swift \
        Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 81 — Scheduler section in Settings; SchedulerEngine injected into environment"
```
