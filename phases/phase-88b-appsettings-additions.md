# Phase 88b — AppSettings Additions Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 88a complete: failing AppSettingsAdditionsTests in place.

Add `MessageDensity` enum and four new properties to `AppSettings` with config.toml persistence.

---

## Write to: Merlin/Config/MessageDensity.swift

```swift
import Foundation

enum MessageDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case comfortable
    case spacious

    var verticalPadding: Double {
        switch self {
        case .compact: return 4
        case .comfortable: return 8
        case .spacious: return 16
        }
    }
}
```

---

## Edit: Merlin/Config/AppSettings.swift

Add four `@Published` properties after `xcalibreToken`:

```swift
    @Published var keepAwake: Bool = false
    @Published var defaultPermissionMode: PermissionMode = .ask
    @Published var notificationsEnabled: Bool = true
    @Published var messageDensity: MessageDensity = .comfortable
```

Add to `ConfigFile` struct:

```swift
        var keepAwake: Bool?
        var defaultPermissionMode: String?
        var notificationsEnabled: Bool?
        var messageDensity: String?
```

Add `CodingKeys`:

```swift
            case keepAwake = "keep_awake"
            case defaultPermissionMode = "default_permission_mode"
            case notificationsEnabled = "notifications_enabled"
            case messageDensity = "message_density"
```

Add to `load(from:)`:

```swift
        if let value = config.keepAwake { keepAwake = value }
        if let value = config.defaultPermissionMode,
           let mode = PermissionMode(rawValue: value) { defaultPermissionMode = mode }
        if let value = config.notificationsEnabled { notificationsEnabled = value }
        if let value = config.messageDensity,
           let density = MessageDensity(rawValue: value) { messageDensity = value == density.rawValue ? density : .comfortable }
```

Simplify the messageDensity load line:

```swift
        if let value = config.messageDensity,
           let density = MessageDensity(rawValue: value) { messageDensity = density }
```

Add to `save(to:)` near the top scalar section:

```swift
        if keepAwake {
            lines.append("keep_awake = true")
        }
        lines.append("default_permission_mode = \(quoted(defaultPermissionMode.rawValue))")
        if !notificationsEnabled {
            lines.append("notifications_enabled = false")
        }
        if messageDensity != .comfortable {
            lines.append("message_density = \(quoted(messageDensity.rawValue))")
        }
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AppSettingsAdditions.*passed|AppSettingsAdditions.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`; all AppSettingsAdditionsTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/MessageDensity.swift \
        Merlin/Config/AppSettings.swift
git commit -m "Phase 88b — AppSettings: keepAwake, defaultPermissionMode, notificationsEnabled, messageDensity"
```
