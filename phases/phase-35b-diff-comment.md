# Phase 35b — Inline Diff Commenting Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 35a complete: failing DiffCommentTests in place.

---

## Write to: Merlin/Engine/DiffComment.swift

```swift
import Foundation

struct DiffComment: Identifiable, Sendable {
    var id: UUID = UUID()
    var lineIndex: Int
    var body: String
    var createdAt: Date = Date()
}
```

---

## Modify: Merlin/Engine/StagingBuffer.swift

Add `comments: [DiffComment]` to `StagedChange`:

```swift
struct StagedChange: Identifiable, Sendable {
    var id: UUID = UUID()
    var path: String
    var kind: ChangeKind
    var before: String?
    var after: String?
    var destinationPath: String?
    var comments: [DiffComment] = []
}
```

Add two new methods to `StagingBuffer` actor:

```swift
func addComment(_ comment: DiffComment, toChange id: UUID) {
    guard let index = pendingChanges.firstIndex(where: { $0.id == id }) else { return }
    pendingChanges[index].comments.append(comment)
}

func commentsAsAgentMessage(_ changeIDs: [UUID]) -> String {
    var parts: [String] = [
        "I've reviewed the staged changes and left inline comments. Please revise accordingly:\n"
    ]
    for id in changeIDs {
        guard let change = pendingChanges.first(where: { $0.id == id }),
              !change.comments.isEmpty else { continue }
        let filename = (change.path as NSString).lastPathComponent
        parts.append("**\(filename)** (`\(change.path)`):")
        for comment in change.comments.sorted(by: { $0.lineIndex < $1.lineIndex }) {
            parts.append("  - Line \(comment.lineIndex + 1): \(comment.body)")
        }
    }
    return parts.joined(separator: "\n")
}
```

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add a new method after `cancel()`:

```swift
func submitDiffComments(changeIDs: [UUID]) -> AsyncStream<AgentEvent> {
    guard let buffer = toolRouter.stagingBuffer else {
        return AsyncStream { $0.finish() }
    }
    return AsyncStream { continuation in
        isRunning = true
        let task = Task { @MainActor in
            defer { self.isRunning = false; self.currentTask = nil }
            let message = await buffer.commentsAsAgentMessage(changeIDs)
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continuation.finish(); return
            }
            do {
                try await self.runLoop(userMessage: message, continuation: continuation)
                continuation.finish()
            } catch is CancellationError {
                continuation.yield(.systemNote("[Interrupted]"))
                continuation.finish()
            } catch {
                continuation.yield(.error(error))
                continuation.finish()
            }
        }
        self.currentTask = task
    }
}
```

---

## Modify: Merlin/Views/DiffPane.swift

Update `StagedChangeView` to support inline commenting. Add a `@State private var pendingComment: String = ""` and a `@State private var commentingLineIndex: Int? = nil`.

In `DiffLineView`, add an `.onTapGesture` that sets `commentingLineIndex` to the tapped line index.
Below the diff lines block, show a comment input field when `commentingLineIndex != nil`:

```swift
if let lineIdx = commentingLineIndex {
    HStack {
        TextField("Comment on line \(lineIdx + 1)…", text: $pendingComment)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        Button("Submit") {
            guard !pendingComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let comment = DiffComment(lineIndex: lineIdx, body: pendingComment)
            Task { await buffer.buffer.addComment(comment, toChange: change.id) }
            pendingComment = ""
            commentingLineIndex = nil
        }
        .font(.caption.weight(.medium))
        Button("Cancel") { commentingLineIndex = nil; pendingComment = "" }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.quinary)
}
```

Add a "Submit Comments" button to `DiffPane`'s footer (next to "Accept All & Commit"):

```swift
if buffer.pendingChanges.contains(where: { !$0.comments.isEmpty }) {
    Button {
        let ids = buffer.pendingChanges.map(\.id)
        Task {
            for await _ in engine.submitDiffComments(changeIDs: ids) {}
        }
    } label: {
        Label("Submit Comments", systemImage: "bubble.left")
    }
    .buttonStyle(.bordered)
}
```

`DiffPane` needs access to the engine — add `let engine: AgenticEngine` to its
initialiser and pass it from `WorkspaceView`.

---

## Modify: project.yml

Add `Merlin/Engine/DiffComment.swift` to Merlin target sources.

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

Expected: `BUILD SUCCEEDED`; `DiffCommentTests` → 6 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/DiffComment.swift \
        Merlin/Engine/StagingBuffer.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/DiffPane.swift \
        Merlin/Views/WorkspaceView.swift \
        project.yml
git commit -m "Phase 35b — inline diff commenting + submitDiffComments"
```
