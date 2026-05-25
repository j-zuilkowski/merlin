# Phase 52 — Toolbar Actions + Notifications

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 51 complete: Reasoning effort + personalization + context tracker in place.

Two features in one phase — both are small and independent:
1. **Toolbar Actions** — named one-click shortcuts (run tests, start server, build) per project
2. **Notifications** — system notifications when agent tasks complete or need approval

No a/b split. Tests in `MerlinTests/Unit/ToolbarActionTests.swift`.

---

## Tests: MerlinTests/Unit/ToolbarActionTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolbarActionTests: XCTestCase {

    // MARK: - ToolbarAction

    func test_toolbarAction_executesCommand() async throws {
        let action = ToolbarAction(id: UUID(), label: "Echo", command: "echo hello", shortcut: nil)
        let result = try await action.run()
        XCTAssertTrue(result.contains("hello"))
    }

    func test_toolbarAction_nonZeroExit_throws() async {
        let action = ToolbarAction(id: UUID(), label: "Fail", command: "/bin/false", shortcut: nil)
        do {
            _ = try await action.run()
            XCTFail("Expected throw on non-zero exit")
        } catch {
            // pass
        }
    }

    // MARK: - ToolbarActionStore

    func test_store_addAndList() async {
        let store = ToolbarActionStore()
        let action = ToolbarAction(id: UUID(), label: "Build", command: "make build", shortcut: "b")
        await store.add(action)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].label, "Build")
    }

    func test_store_remove() async {
        let store = ToolbarActionStore()
        let id = UUID()
        let action = ToolbarAction(id: id, label: "Test", command: "make test", shortcut: nil)
        await store.add(action)
        await store.remove(id: id)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - NotificationEngine

    func test_notificationEngine_requestsAuthorization() async {
        let engine = NotificationEngine()
        // Just verify it doesn't crash — authorization dialog may or may not appear in test
        await engine.requestAuthorization()
    }

    func test_notificationEngine_postDoesNotThrow() async {
        let engine = NotificationEngine()
        await engine.post(
            title: "Task complete",
            body: "The agent finished successfully.",
            identifier: "test-notif-\(UUID().uuidString)"
        )
        // No assertion — just confirm no crash
    }
}
```

---

## New files

### Merlin/Toolbar/ToolbarAction.swift

```swift
import Foundation

struct ToolbarAction: Identifiable, Codable, Sendable {
    var id: UUID
    var label: String
    var command: String
    var shortcut: String?  // single character, used as ⌘+shortcut

    enum CodingKeys: String, CodingKey {
        case id, label, command, shortcut
    }

    // Runs the command in a shell and returns combined stdout.
    // Throws ShellError on non-zero exit.
    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data   = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ToolbarActionError.nonZeroExit(
                        Int(process.terminationStatus), output
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum ToolbarActionError: Error, LocalizedError {
    case nonZeroExit(Int, String)

    var errorDescription: String? {
        if case .nonZeroExit(let code, let output) = self {
            return "Command exited \(code): \(output.prefix(200))"
        }
        return nil
    }
}
```

### Merlin/Toolbar/ToolbarActionStore.swift

```swift
import Foundation

actor ToolbarActionStore {
    private var actions: [UUID: ToolbarAction] = [:]
    private var order: [UUID] = []

    func add(_ action: ToolbarAction) {
        guard actions[action.id] == nil else { return }
        actions[action.id] = action
        order.append(action.id)
    }

    func remove(id: UUID) {
        actions.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    func all() -> [ToolbarAction] {
        order.compactMap { actions[$0] }
    }

    func update(_ action: ToolbarAction) {
        guard actions[action.id] != nil else { return }
        actions[action.id] = action
    }
}
```

### Merlin/Notifications/NotificationEngine.swift

```swift
import Foundation
import UserNotifications

// Sends macOS system notifications when agent tasks complete or need user approval.
actor NotificationEngine {

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func post(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Convenience: notify that an agent session completed.
    func notifyTaskComplete(sessionLabel: String) async {
        await post(
            title: "Task complete",
            body:  "\(sessionLabel) finished.",
            identifier: "task-complete-\(UUID().uuidString)"
        )
    }

    // Convenience: notify that an approval prompt is waiting.
    func notifyApprovalNeeded(toolName: String) async {
        await post(
            title: "Approval needed",
            body:  "\(toolName) is waiting for your approval.",
            identifier: "approval-\(UUID().uuidString)"
        )
    }
}
```

---

## UI: Toolbar actions bar

Add a horizontal `HStack` of buttons above or below the chat input, visible when
`ToolbarActionStore` has entries for the current project root. Each button:
- Shows `action.label`
- Has optional keyboard shortcut `⌘+action.shortcut`
- Runs `action.run()` and appends stdout to the session as a system message

```swift
// In ChatView or SessionView toolbar area:
HStack(spacing: 8) {
    ForEach(toolbarActions) { action in
        Button(action.label) {
            Task {
                do {
                    let output = try await action.run()
                    // Append as a system message to the session
                } catch {
                    // Show error inline
                }
            }
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(
            action.shortcut.flatMap { KeyEquivalent($0.first ?? "?") } ?? .return,
            modifiers: action.shortcut != nil ? .command : []
        )
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all ToolbarActionTests pass.

## Commit
```bash
git add MerlinTests/Unit/ToolbarActionTests.swift \
        Merlin/Toolbar/ToolbarAction.swift \
        Merlin/Toolbar/ToolbarActionStore.swift \
        Merlin/Notifications/NotificationEngine.swift
git commit -m "Phase 52 — Toolbar Actions + Notifications"
```
