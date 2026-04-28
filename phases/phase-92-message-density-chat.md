# Phase 92 — Apply messageDensity to ChatView Message Rows

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 91 complete: ToolRegistry.shared.registerBuiltins() called at launch.

`AppSettings.messageDensity` is persisted and exposed in Appearance settings but its
`verticalPadding` computed property is never read by ChatView. Message rows always use
a fixed padding.

---

## Edit: Merlin/Views/ChatView.swift

Find the `ChatEntryRow` view (or equivalent message row view). Add `@ObservedObject` (or
read via `AppSettings.shared`) to pick up `messageDensity`:

If the row is a struct, add:

```swift
@ObservedObject private var settings = AppSettings.shared
```

Then in the view body, find the `.padding(.vertical, ...)` modifier on the row container.
Replace the hard-coded value with:

```swift
.padding(.vertical, settings.messageDensity.verticalPadding)
```

If there is no existing `.padding(.vertical, ...)`, wrap the row content in:

```swift
.padding(.vertical, settings.messageDensity.verticalPadding)
```

Apply it at the outermost container of each message row (the `HStack` or `VStack` that
contains the bubble/text), not to inner elements.

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
git add Merlin/Views/ChatView.swift
git commit -m "Phase 92 — Apply messageDensity.verticalPadding to ChatView message rows"
```
