# Task diag-10b — Toolbar Actions Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Task diag-10a complete.

User-configurable toolbar buttons that run arbitrary shell commands. Persisted as JSON
at a path configured in AppSettings (default `~/.merlin/toolbar-actions.json`).

---

## Write to: Merlin/Toolbar/ToolbarAction.swift

```swift
import Foundation

struct ToolbarAction: Identifiable, Codable, Sendable {
    var id: UUID
    var label: String
    var command: String
    var shortcut: String?

    /// Execute the shell command and return stdout+stderr combined.
    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing:
                        ToolbarActionError.nonZeroExit(Int(process.terminationStatus), output))
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
        switch self {
        case .nonZeroExit(let code, let output):
            return "Command exited \(code): \(output.prefix(200))"
        }
    }
}
```

---

## Write to: Merlin/Toolbar/ToolbarActionStore.swift

```swift
import Foundation

/// Ordered, actor-isolated store for user-defined toolbar actions.
/// Persisted as a JSON array at a caller-supplied path.
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

    func load(from path: String) async {
        guard let data = FileManager.default.contents(atPath: path),
              let loaded = try? JSONDecoder().decode([ToolbarAction].self, from: data) else { return }
        actions.removeAll()
        order.removeAll()
        for action in loaded { add(action) }
    }

    func save(to path: String) async {
        let all = all()
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
```

## Integration
- `AppState` creates a `ToolbarActionStore` and loads from `~/.merlin/toolbar-actions.json` at launch.
- The toolbar renders `store.all()` as `Button` items. Clicking runs `action.run()` and
  posts the output as a system note in the active session.
- Adding/removing/reordering actions in Settings calls `store.add/remove/update` then `store.save(to:)`.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ToolbarAction|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Toolbar/ToolbarAction.swift \
        Merlin/Toolbar/ToolbarActionStore.swift \
        tasks/task-diag-10b-toolbar-actions.md
git commit -m "Task diag-10b — ToolbarAction + ToolbarActionStore"
```
