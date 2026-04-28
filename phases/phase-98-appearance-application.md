# Phase 98 — Apply AppTheme and Font Settings to the UI

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 97 complete: HookEngine wired into main AgenticEngine loop.

`AppSettings.appearance.theme` (system/light/dark) and `appearance.fontSize`/`fontName`
are persisted and shown in the Appearance settings section. However:
- `.preferredColorScheme()` is never set on any view — theme toggle has no effect
- Font settings are never applied to chat text

---

## Edit: Merlin/Views/WorkspaceView.swift

Apply theme and font to the workspace root view. At the outermost container in
`WorkspaceView.body`, add:

```swift
    var body: some View {
        // ... existing content ...
        .preferredColorScheme(AppSettings.shared.appearance.theme.colorScheme)
        .font(.system(size: AppSettings.shared.appearance.fontSize))
    }
```

`AppTheme.colorScheme` is a computed property to add (see below).

---

## Edit: Merlin/Config/AppearanceSettings.swift

Add a `colorScheme` computed property to `AppTheme`:

```swift
extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
```

`preferredColorScheme(nil)` means "follow system" — exactly what `.system` should do.

---

## Edit: Merlin/Views/WorkspaceView.swift (font tracking)

To make theme and font changes live (they must react to `AppSettings` changes):

Add `@ObservedObject private var settings = AppSettings.shared` to `WorkspaceView`.

Then in `.body`, reference both:

```swift
.preferredColorScheme(settings.appearance.theme.colorScheme)
.font(.system(size: settings.appearance.fontSize))
```

If `appearance.fontName` is non-empty, apply a named font instead:

```swift
.font(settings.appearance.fontName.isEmpty
    ? .system(size: settings.appearance.fontSize)
    : .custom(settings.appearance.fontName, size: settings.appearance.fontSize))
```

---

## Edit: Merlin/App/MerlinApp.swift

The picker window also needs theme applied. Add to the picker `WindowGroup`:

```swift
        WindowGroup("Merlin", id: "picker") {
            ProjectPickerView()
                .environmentObject(recents)
                .preferredColorScheme(AppSettings.shared.appearance.theme.colorScheme)
        }
```

Since `MerlinApp` is not `@MainActor` and `AppSettings.shared` is, reading it directly
in a view body (which runs on the main actor) is fine. If the compiler objects, wrap
in a helper view.

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
git add Merlin/Views/WorkspaceView.swift \
        Merlin/Config/AppearanceSettings.swift \
        Merlin/App/MerlinApp.swift
git commit -m "Phase 98 — Apply AppTheme (preferredColorScheme) and font settings to the UI"
```
