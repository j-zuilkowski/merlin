# Phase 33b — DiffEngine + DiffPane Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 33a complete: failing DiffEngineTests in place.

---

## Write to: Merlin/Engine/DiffEngine.swift

```swift
import Foundation

// MARK: - Types

enum DiffLine: Equatable {
    case context(String)
    case added(String)
    case removed(String)
}

struct DiffHunk: Identifiable {
    var id: UUID = UUID()
    var lines: [DiffLine]

    var addedCount:   Int { lines.filter { if case .added   = $0 { true } else { false } }.count }
    var removedCount: Int { lines.filter { if case .removed = $0 { true } else { false } }.count }
}

// MARK: - DiffEngine

enum DiffEngine {

    /// Compute a unified diff between two texts. Returns an array of DiffHunks,
    /// each representing a contiguous region of change with context lines around it.
    static func diff(before: String, after: String, contextLines: Int = 3) -> [DiffHunk] {
        let lhs = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let rhs = after.isEmpty  ? [] : after.components(separatedBy: "\n")

        if lhs.isEmpty && rhs.isEmpty { return [] }

        let ses = lcs(lhs, rhs)
        return buildHunks(lhs: lhs, rhs: rhs, ses: ses, context: contextLines)
    }

    // MARK: - LCS (Myers diff, simplified O(n*m) DP)

    private static func lcs(_ a: [String], _ b: [String]) -> [[Bool]] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
            }
        }
        // Back-track to build edit script
        var inLCS = Array(repeating: Array(repeating: false, count: n + 1), count: m + 1)
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                inLCS[i][j] = true
                i -= 1; j -= 1
            } else if dp[i-1][j] >= dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return inLCS
    }

    private static func buildHunks(lhs: [String], rhs: [String],
                                   ses: [[Bool]], context: Int) -> [DiffHunk] {
        // Flatten to a sequence of DiffLines
        var flat: [DiffLine] = []
        var i = 1, j = 1
        while i <= lhs.count || j <= rhs.count {
            if i <= lhs.count && j <= rhs.count && ses[i][j] {
                flat.append(.context(lhs[i-1]))
                i += 1; j += 1
            } else if j <= rhs.count &&
                      (i > lhs.count || (i <= lhs.count && !ses[i][j])) {
                flat.append(.added(rhs[j-1]))
                j += 1
            } else {
                flat.append(.removed(lhs[i-1]))
                i += 1
            }
        }

        // Group into hunks separated by context windows
        return groupIntoHunks(flat, context: context)
    }

    private static func groupIntoHunks(_ lines: [DiffLine], context: Int) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var current: [DiffLine] = []
        var contextBuffer: [DiffLine] = []

        for line in lines {
            switch line {
            case .context:
                if current.isEmpty {
                    contextBuffer.append(line)
                    if contextBuffer.count > context { contextBuffer.removeFirst() }
                } else {
                    current.append(line)
                    // If we've accumulated more than 2*context trailing context lines, flush
                    let trailingCtx = current.reversed().prefix(while: {
                        if case .context = $0 { true } else { false }
                    }).count
                    if trailingCtx >= context * 2 {
                        let keepTrailing = Array(current.suffix(context))
                        current = Array(current.dropLast(trailingCtx - context))
                        hunks.append(DiffHunk(lines: current))
                        current = keepTrailing
                    }
                }
            case .added, .removed:
                current += contextBuffer
                contextBuffer = []
                current.append(line)
            }
        }

        if !current.isEmpty {
            // Trim trailing context to `context` lines
            var trimmed = current
            while trimmed.count > 1,
                  case .context = trimmed.last!,
                  trimmed.suffix(context + 1).allSatisfy({ if case .context = $0 { true } else { false } }) {
                trimmed.removeLast()
            }
            hunks.append(DiffHunk(lines: trimmed))
        }

        return hunks
    }
}
```

---

## Write to: Merlin/Views/DiffPane.swift

```swift
import SwiftUI

struct DiffPane: View {
    @ObservedObject var buffer: StagingBufferWrapper
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Staged Changes")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !buffer.pendingChanges.isEmpty {
                    let stats = totalStats
                    HStack(spacing: 4) {
                        Text("+\(stats.added)").foregroundStyle(.green).font(.caption)
                        Text("−\(stats.removed)").foregroundStyle(.red).font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if buffer.pendingChanges.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("No staged changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(buffer.pendingChanges) { change in
                            StagedChangeView(
                                change: change,
                                onAccept: { Task { try? await buffer.buffer.accept(change.id) } },
                                onReject: { Task { await buffer.buffer.reject(change.id) } }
                            )
                        }
                    }
                    .padding(8)
                }

                Divider()

                // Footer
                HStack(spacing: 6) {
                    Button {
                        Task { await buffer.buffer.rejectAll() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Reject All")

                    Button {
                        Task {
                            try? await buffer.buffer.acceptAll()
                            onCommit()
                        }
                    } label: {
                        Label("Accept All & Commit", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }
        }
    }

    private var totalStats: (added: Int, removed: Int) {
        buffer.pendingChanges.reduce((0, 0)) { acc, change in
            let hunks = DiffEngine.diff(before: change.before ?? "", after: change.after ?? "")
            let a = hunks.reduce(0) { $0 + $1.addedCount }
            let r = hunks.reduce(0) { $0 + $1.removedCount }
            return (acc.0 + a, acc.1 + r)
        }
    }
}

private struct StagedChangeView: View {
    let change: StagedChange
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // File header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: fileIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((change.path as NSString).lastPathComponent)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                    let hunks = DiffEngine.diff(before: change.before ?? "", after: change.after ?? "")
                    let a = hunks.reduce(0) { $0 + $1.addedCount }
                    let r = hunks.reduce(0) { $0 + $1.removedCount }
                    if a > 0 { Text("+\(a)").font(.caption).foregroundStyle(.green) }
                    if r > 0 { Text("−\(r)").font(.caption).foregroundStyle(.red) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Diff lines
            if isExpanded {
                let hunks = DiffEngine.diff(before: change.before ?? "", after: change.after ?? "")
                VStack(spacing: 0) {
                    ForEach(hunks) { hunk in
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
            }

            // Action buttons
            HStack(spacing: 4) {
                Button("Accept", action: onAccept)
                    .buttonStyle(DiffActionButtonStyle(color: .green))
                Button("Reject", action: onReject)
                    .buttonStyle(DiffActionButtonStyle(color: .red))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quinary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator, lineWidth: 0.5))
    }

    private var fileIcon: String {
        switch change.kind {
        case .create: return "doc.badge.plus"
        case .delete: return "doc.badge.minus"
        case .move:   return "arrow.right.doc.on.clipboard"
        case .write:  return "doc.text"
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .frame(width: 14, alignment: .center)
                .foregroundStyle(prefixColor)
            Text(content)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(background)
    }
    private var prefix: String {
        switch line { case .added: "+"; case .removed: "−"; case .context: " " }
    }
    private var prefixColor: Color {
        switch line { case .added: .green; case .removed: .red; case .context: .secondary }
    }
    private var content: String {
        switch line { case .added(let s), .removed(let s), .context(let s): s }
    }
    private var background: Color {
        switch line {
        case .added:   return .green.opacity(0.08)
        case .removed: return .red.opacity(0.08)
        case .context: return .clear
        }
    }
}

private struct DiffActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(configuration.isPressed ? 0.25 : 0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - StagingBufferWrapper
// @MainActor-observable wrapper around the StagingBuffer actor so SwiftUI can react
// to changes without directly observing an actor.

@MainActor
final class StagingBufferWrapper: ObservableObject {
    let buffer: StagingBuffer
    @Published private(set) var pendingChanges: [StagedChange] = []

    init(buffer: StagingBuffer) {
        self.buffer = buffer
        Task { await refresh() }
    }

    func refresh() async {
        pendingChanges = await buffer.pendingChanges
    }
}
```

---

## Modify: Merlin/Views/WorkspaceView.swift

Add `DiffPane` to the workspace layout alongside the existing `ContentView`:

```swift
HSplitView {
    SessionSidebar()
        .environmentObject(sessionManager)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

    ContentView()
        .environmentObject(session.appState)
        .environmentObject(session.appState.registry)
        .frame(minWidth: 500)

    DiffPane(
        buffer: StagingBufferWrapper(buffer: session.stagingBuffer),
        onCommit: { /* commit flow in phase 36 */ }
    )
    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
}
```

`LiveSession` needs to expose `stagingBuffer` as a computed property returning the
`StagingBuffer` stored on its `appState.engine.toolRouter.stagingBuffer`.

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Engine/DiffEngine.swift`
- `Merlin/Views/DiffPane.swift`

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

Expected: `BUILD SUCCEEDED`; `DiffEngineTests` → 9 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/DiffEngine.swift \
        Merlin/Views/DiffPane.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/Sessions/LiveSession.swift \
        project.yml
git commit -m "Phase 33b — DiffEngine + DiffPane"
```
