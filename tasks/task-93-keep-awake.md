# Phase 93 — Enforce keepAwake via IOPMAssertion

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 92 complete: messageDensity applied to ChatView.

`AppSettings.keepAwake` is persisted and toggled in General settings but no
`IOPMAssertionCreateWithName` call exists anywhere — the Mac sleeps regardless of
the setting.

---

## Write to: Merlin/System/KeepAwakeManager.swift

```swift
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    func apply(_ keepAwake: Bool) {
        if keepAwake {
            enable()
        } else {
            disable()
        }
    }

    private func enable() {
        guard !isHeld else { return }
        let name = "Merlin long session" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isHeld = true
        }
    }

    private func disable() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }
}
```

---

## Edit: Merlin/App/AppState.swift

Add a stored observer for `keepAwake` changes. In `init`, after the existing
`registryCancellable` setup, add:

```swift
        KeepAwakeManager.shared.apply(AppSettings.shared.keepAwake)
        AppSettings.shared.$keepAwake
            .sink { KeepAwakeManager.shared.apply($0) }
            .store(in: &cancellables)
```

Add `private var cancellables = Set<AnyCancellable>()` as a stored property if it doesn't
already exist (alongside the existing `registryCancellable`).

If `AppState` already has a `Set<AnyCancellable>` property, use that. If it only has
`registryCancellable: AnyCancellable?`, convert to a Set or add a second stored property:

```swift
    private var keepAwakeCancellable: AnyCancellable?
```

And store:

```swift
        keepAwakeCancellable = AppSettings.shared.$keepAwake
            .sink { KeepAwakeManager.shared.apply($0) }
```

---

## Edit: project.yml

Add `Merlin/System/KeepAwakeManager.swift` to the `Merlin` target sources if the directory
is not already a glob-included path. Check whether `Merlin/System/` already exists as a
source group; if not, ensure the file is reachable by the existing source glob pattern.

If `project.yml` uses `sources: Merlin/` as a recursive glob, no change is needed.

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
git add Merlin/System/KeepAwakeManager.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 93 — KeepAwakeManager: enforce keepAwake via IOPMAssertion"
```
