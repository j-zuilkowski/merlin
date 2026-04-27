import SwiftUI

struct DiffPane: View {
    @ObservedObject var buffer: StagingBufferWrapper
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
                                onAccept: {
                                    Task {
                                        try? await buffer.buffer.accept(change.id)
                                        await buffer.refresh()
                                    }
                                },
                                onReject: {
                                    Task {
                                        await buffer.buffer.reject(change.id)
                                        await buffer.refresh()
                                    }
                                }
                            )
                        }
                    }
                    .padding(8)
                }

                Divider()

                HStack(spacing: 6) {
                    Button {
                        Task {
                            await buffer.buffer.rejectAll()
                            await buffer.refresh()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Reject All")

                    Button {
                        Task {
                            try? await buffer.buffer.acceptAll()
                            await buffer.refresh()
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
        .task { await buffer.refresh() }
    }

    private var totalStats: (added: Int, removed: Int) {
        buffer.pendingChanges.reduce((0, 0)) { acc, change in
            let hunks = DiffEngine.diff(before: change.before ?? "", after: change.after ?? "")
            let added = hunks.reduce(0) { $0 + $1.addedCount }
            let removed = hunks.reduce(0) { $0 + $1.removedCount }
            return (acc.0 + added, acc.1 + removed)
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
                    let added = hunks.reduce(0) { $0 + $1.addedCount }
                    let removed = hunks.reduce(0) { $0 + $1.removedCount }
                    if added > 0 { Text("+\(added)").font(.caption).foregroundStyle(.green) }
                    if removed > 0 { Text("−\(removed)").font(.caption).foregroundStyle(.red) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
            }
            .buttonStyle(.plain)

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
        case .create:
            return "doc.badge.plus"
        case .delete:
            return "doc.badge.minus"
        case .move:
            return "arrow.right.doc.on.clipboard"
        case .write:
            return "doc.text"
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
        switch line {
        case .added:
            return "+"
        case .removed:
            return "−"
        case .context:
            return " "
        }
    }

    private var prefixColor: Color {
        switch line {
        case .added:
            return .green
        case .removed:
            return .red
        case .context:
            return .secondary
        }
    }

    private var content: String {
        switch line {
        case .added(let s), .removed(let s), .context(let s):
            return s
        }
    }

    private var background: Color {
        switch line {
        case .added:
            return .green.opacity(0.08)
        case .removed:
            return .red.opacity(0.08)
        case .context:
            return .clear
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
