import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var coordinator: WorkspaceCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(coordinator.projectManagers, id: \.projectRef.path) { mgr in
                        ProjectSection(mgr: mgr, coordinator: coordinator)
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.sessionList)

            Divider()

            Button {
                TelemetryEmitter.shared.emitGUIAction("tap",
                    identifier: AccessibilityID.newSessionButton)
                coordinator.showingProjectPicker = true
            } label: {
                Label("New Project Workspace", systemImage: "plus.square.on.square")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.newSessionButton)
            .padding(8)
        }
        .background(.windowBackground)
    }
}

// MARK: - Project section

private struct ProjectSection: View {
    @ObservedObject var mgr: SessionManager
    let coordinator: WorkspaceCoordinator

    @State private var showHeaderPopover = false
    @State private var showArchived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable project header
            Button {
                showHeaderPopover = true
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHeaderPopover, arrowEdge: .trailing) {
                ProjectHeaderPopover(mgr: mgr, coordinator: coordinator,
                                     isPresented: $showHeaderPopover)
            }

            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("Sessions")

                ForEach(mgr.liveSessions) { session in
                    LiveSessionRow(session: session,
                                   isActive: session.id == coordinator.activeSession?.id)
                        .onTapGesture { coordinator.setActiveSession(session) }
                        .contextMenu {
                            Button("Close Session", role: .destructive) {
                                Task { await mgr.closeSession(session.id) }
                            }
                        }
                }

                // Prior sessions (disk records not currently live)
                let liveIDs = Set(mgr.liveSessions.map(\.id))
                let prior = mgr.sessionStore.activeSessions.filter { !liveIDs.contains($0.id) }

                if !prior.isEmpty {
                    SectionLabel("Prior Sessions").padding(.top, 6)

                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture {
                                Task {
                                    let live = await mgr.restore(session: session)
                                    coordinator.setActiveSession(live)
                                }
                            }
                            .contextMenu {
                                Button("Resume") {
                                    Task {
                                        let live = await mgr.restore(session: session)
                                        coordinator.setActiveSession(live)
                                    }
                                }
                                Divider()
                                Button("Archive") {
                                    try? mgr.sessionStore.archive(session.id)
                                }
                                Button("Delete", role: .destructive) {
                                    try? mgr.sessionStore.delete(session.id)
                                }
                            }
                    }
                }

                // Archived sessions (collapsible)
                let archived = mgr.sessionStore.archivedSessions
                if !archived.isEmpty {
                    Button {
                        showArchived.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Show archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)

                    if showArchived {
                        ForEach(archived) { session in
                            PriorSessionRow(session: session, dimmed: true)
                                .contextMenu {
                                    Button("Recall") {
                                        try? mgr.sessionStore.unarchive(session.id)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        try? mgr.sessionStore.delete(session.id)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Project header popover

private struct ProjectHeaderPopover: View {
    let mgr: SessionManager
    let coordinator: WorkspaceCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isPresented = false
                Task {
                    let session = await mgr.newSession()
                    coordinator.setActiveSession(session)
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                isPresented = false
                coordinator.removeProject(mgr.projectRef)
            } label: {
                Label("Close Project", systemImage: "xmark")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
    }
}

// MARK: - Row views

private struct LiveSessionRow: View {
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

private struct PriorSessionRow: View {
    let session: Session
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(session.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(dimmed ? .tertiary : .secondary)
                .lineLimit(1)
            Spacer()
            Text(RelativeTimestampFormatter.string(from: session.updatedAt))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
        .contentShape(Rectangle())
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
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
