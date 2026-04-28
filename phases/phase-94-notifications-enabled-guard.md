# Phase 94 — Guard NotificationEngine on notificationsEnabled

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 93 complete: KeepAwakeManager enforces keepAwake via IOPMAssertion.

`AppSettings.notificationsEnabled` is persisted and toggled in General settings but
`NotificationEngine.post()` never checks it — notifications fire regardless of the toggle.

---

## Edit: Merlin/Notifications/NotificationEngine.swift

In `post(title:body:identifier:)`, add a guard at the top of the method body:

```swift
    func post(title: String, body: String, identifier: String) async {
        guard isNotificationEnvironmentAvailable else { return }
        guard await MainActor.run(body: { AppSettings.shared.notificationsEnabled }) else { return }
        ...
    }
```

The `AppSettings.shared.notificationsEnabled` property is `@Published` on a `@MainActor`
class, so it must be read on the main actor. Use `await MainActor.run { }` since
`NotificationEngine` is an actor (not `@MainActor`).

Full replacement for `post(title:body:identifier:)`:

```swift
    func post(title: String, body: String, identifier: String) async {
        guard isNotificationEnvironmentAvailable else { return }
        guard await MainActor.run(body: { AppSettings.shared.notificationsEnabled }) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
```

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
git add Merlin/Notifications/NotificationEngine.swift
git commit -m "Phase 94 — NotificationEngine: guard post() on AppSettings.notificationsEnabled"
```
