# Phase 32b — StagingBuffer Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 32a complete: failing StagingBufferTests in place.

---

## Write to: Merlin/Engine/StagingBuffer.swift

```swift
import Foundation

enum ChangeKind: String, Codable, Sendable {
    case write
    case create
    case delete
    case move
}

struct StagedChange: Identifiable, Sendable {
    var id: UUID = UUID()
    var path: String
    var kind: ChangeKind
    var before: String?
    var after: String?
    var destinationPath: String?  // used for .move
}

actor StagingBuffer {
    private(set) var pendingChanges: [StagedChange] = []

    func stage(_ change: StagedChange) {
        pendingChanges.append(change)
    }

    func accept(_ id: UUID) async throws {
        guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
        let change = pendingChanges[index]
        try applyChange(change)
        pendingChanges.remove(at: index)
    }

    func reject(_ id: UUID) {
        pendingChanges.removeAll { $0.id == id }
    }

    func acceptAll() async throws {
        for change in pendingChanges {
            try applyChange(change)
        }
        pendingChanges.removeAll()
    }

    func rejectAll() {
        pendingChanges.removeAll()
    }

    // MARK: - Private

    private func applyChange(_ change: StagedChange) throws {
        let fm = FileManager.default
        switch change.kind {
        case .write, .create:
            let content = change.after ?? ""
            let dir = (change.path as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: change.path, atomically: true, encoding: .utf8)
        case .delete:
            if fm.fileExists(atPath: change.path) {
                try fm.removeItem(atPath: change.path)
            }
        case .move:
            guard let dest = change.destinationPath else {
                throw CocoaError(.fileNoSuchFile)
            }
            try fm.moveItem(atPath: change.path, toPath: dest)
        }
    }
}
```

---

## Modify: Merlin/Engine/ToolRouter.swift

Add `stagingBuffer` and `permissionMode` properties, and intercept file-write tool
calls when staging is active.

Add after existing stored properties:

```swift
var stagingBuffer: StagingBuffer?
var permissionMode: PermissionMode = .ask
```

In `dispatch(call:)`, before executing file-write tools, check whether to stage:

```swift
func dispatch(call: ToolCall) async -> ToolResult {
    let name = call.function.name
    if shouldStage(name) {
        return await stageFileWrite(call: call)
    }
    // ... existing dispatch logic unchanged
}

private func shouldStage(_ toolName: String) -> Bool {
    guard stagingBuffer != nil else { return false }
    guard permissionMode == .ask || permissionMode == .plan else { return false }
    return ["write_file", "create_file", "delete_file", "move_file"].contains(toolName)
}

private func stageFileWrite(call: ToolCall) async -> ToolResult {
    guard let buffer = stagingBuffer else {
        return ToolResult(toolCallID: call.id, content: "error: no staging buffer")
    }
    do {
        let args = try JSONDecoder().decode([String: String].self,
                                            from: Data(call.function.arguments.utf8))
        let path = args["path"] ?? args["source_path"] ?? ""
        let kind = changeKind(for: call.function.name)
        let before = path.isEmpty ? nil : (try? String(contentsOfFile: path, encoding: .utf8))
        let change = StagedChange(
            path: path,
            kind: kind,
            before: before,
            after: args["content"] ?? args["new_content"],
            destinationPath: args["destination_path"]
        )
        await buffer.stage(change)
        return ToolResult(toolCallID: call.id,
                          content: "Staged \(kind.rawValue) for \(path) — awaiting review")
    } catch {
        return ToolResult(toolCallID: call.id, content: "staging error: \(error)")
    }
}

private func changeKind(for toolName: String) -> ChangeKind {
    switch toolName {
    case "create_file": return .create
    case "delete_file": return .delete
    case "move_file":   return .move
    default:            return .write
    }
}
```

---

## Modify: Merlin/Sessions/LiveSession.swift

Wire the `StagingBuffer` through to the engine's `ToolRouter`:

```swift
let stagingBuffer = StagingBuffer()

var permissionMode: PermissionMode = .ask {
    didSet {
        appState.engine.permissionMode = permissionMode
        appState.engine.toolRouter.permissionMode = permissionMode
    }
}

init(projectRef: ProjectRef) {
    // ... existing init
    // Wire staging buffer into tool router
    appState.engine.toolRouter.stagingBuffer = stagingBuffer
    appState.engine.toolRouter.permissionMode = .ask
}
```

(`AgenticEngine` needs to expose `toolRouter` as `internal` — add `var toolRouter` if
it is currently `private`. Only the `private(set)` qualifier is needed.)

---

## Modify: project.yml

Add `Merlin/Engine/StagingBuffer.swift` to Merlin target sources.

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `StagingBufferTests` → 10 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/StagingBuffer.swift \
        Merlin/Engine/ToolRouter.swift \
        Merlin/Sessions/LiveSession.swift \
        project.yml
git commit -m "Phase 32b — StagingBuffer actor + ToolRouter intercept"
```
