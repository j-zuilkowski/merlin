import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var mgr: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.purple)
                    .frame(width: 8, height: 8)
                Text(mgr.projectRef.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(mgr.liveSessions) { session in
                        SessionRowView(session: session,
                                       isActive: session.id == mgr.activeSessionID)
                            .onTapGesture { mgr.switchSession(to: session.id) }
                            .contextMenu {
                                Button("Close Session", role: .destructive) {
                                    Task { await mgr.closeSession(session.id) }
                                }
                            }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            Divider()

            Button {
                Task { await mgr.newSession() }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .background(.windowBackground)
    }
}

private struct SessionRowView: View {
    @ObservedObject var session: LiveSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    PermissionModeBadge(mode: session.permissionMode)
                    if session.appState.toolActivityState != .idle {
                        Circle()
                            .fill(.purple)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct PermissionModeBadge: View {
    let mode: PermissionMode

    var body: some View {
        Text(mode.label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(mode.color.opacity(0.15))
            .foregroundStyle(mode.color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
