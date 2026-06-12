import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var coordinator: WorkspaceCoordinator
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(coordinator.projectManagers, id: \.projectRef.path) { mgr in
                        ProjectSection(
                            mgr: mgr,
                            sessionStore: mgr.sessionStore,
                            coordinator: coordinator
                        )
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.sessionList)

            Divider()

            if let appState = coordinator.activeSession?.appState {
                ActiveSessionSlotStatusPanel(
                    appState: appState,
                    slotAssignments: settings.slotAssignments
                )
            } else {
                SlotStatusPanel(
                    slotAssignments: [:],
                    displayNameForProviderID: { $0 }
                )
            }

            Divider()

            Button {
                TelemetryEmitter.shared.emitGUIAction("tap",
                    identifier: AccessibilityID.newSessionButton)
                coordinator.showingProjectPicker = true
            } label: {
                Label("New Project Workspace", systemImage: "plus.square.on.square")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.newSessionButton)
            .padding(8)
        }
        .background(.windowBackground)
    }
}

private struct ActiveSessionSlotStatusPanel: View {
    @ObservedObject var appState: AppState
    let slotAssignments: [AgentSlot: String]

    var body: some View {
        SlotStatusPanel(
            slotAssignments: slotAssignments,
            slotRuntimeStates: appState.slotRuntimeStates,
            displayNameForProviderID: { providerID in
                appState.registry.displayName(for: providerID)
            },
            isProviderReadyForUse: { providerID in
                appState.registry.isReadyForUse(providerID)
            }
        )
    }
}

// MARK: - Project section

private struct ProjectSection: View {
    @ObservedObject var mgr: SessionManager
    @ObservedObject var sessionStore: SessionStore
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
                        .accessibilityHidden(true)
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
            .accessibilityIdentifier(AccessibilityID.sessionProjectHeaderPrefix + mgr.projectRef.path)
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

                if let active = coordinator.activeSession,
                   mgr.liveSessions.contains(where: { $0.id == active.id }) {
                    SubagentSectionHost(sidebar: active.subagentSidebar)
                        .padding(.top, 6)
                }

                // Prior sessions (disk records not currently live)
                let liveIDs = Set(mgr.liveSessions.map(\.id))
                let prior = sessionStore.activeSessions.filter { !liveIDs.contains($0.id) }

                if !prior.isEmpty {
                    SectionLabel("Prior Sessions").padding(.top, 6)

                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture {
                                if let existing = mgr.liveSessions.first(where: {
                                    $0.originalSessionID == session.id
                                }) {
                                    coordinator.setActiveSession(existing)
                                    return
                                }
                                Task {
                                    let live = await mgr.restore(session: session)
                                    coordinator.setActiveSession(live)
                                }
                            }
                            .contextMenu {
                                Button("Resume") {
                                    if let existing = mgr.liveSessions.first(where: {
                                        $0.originalSessionID == session.id
                                    }) {
                                        coordinator.setActiveSession(existing)
                                        return
                                    }
                                    Task {
                                        let live = await mgr.restore(session: session)
                                        coordinator.setActiveSession(live)
                                    }
                                }
                                Divider()
                                Button("Archive") {
                                    try? sessionStore.archive(session.id)
                                }
                                Button("Delete", role: .destructive) {
                                    try? sessionStore.delete(session.id)
                                }
                            }
                    }
                }

                // Archived sessions (collapsible)
                let archived = sessionStore.archivedSessions
                if !archived.isEmpty {
                    Button {
                        showArchived.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.accessibleSecondary)
                            Text("Show archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.accessibleSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.sessionArchivedTogglePrefix + mgr.projectRef.path)

                    if showArchived {
                        ForEach(archived) { session in
                            PriorSessionRow(session: session, dimmed: true)
                                .contextMenu {
                                    Button("Recall") {
                                        try? sessionStore.unarchive(session.id)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        try? sessionStore.delete(session.id)
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

// MARK: - Subagents

private struct SubagentSectionHost: View {
    @ObservedObject var sidebar: SubagentSidebarViewModel

    var body: some View {
        if !sidebar.workerEntries.isEmpty {
            SubagentSection(sidebar: sidebar)
        }
    }
}

private struct SubagentSection: View {
    @ObservedObject var sidebar: SubagentSidebarViewModel

    private var selectedEntry: SubagentSidebarEntry? {
        guard let selectedEntryID = sidebar.selectedEntryID else { return nil }
        return sidebar.workerEntries.first { $0.id == selectedEntryID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Active Subagents")

            ForEach(sidebar.workerEntries) { entry in
                SubagentSidebarRowView(entry: entry, isSelected: entry.id == sidebar.selectedEntryID)
                    .onTapGesture { sidebar.select(id: entry.id) }
            }

            if let selectedEntry {
                WorkerDiffView(entry: selectedEntry)
                    .frame(height: 180)
            }
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
            .accessibilityIdentifier(AccessibilityID.sessionProjectNewButton)

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
            .accessibilityIdentifier(AccessibilityID.sessionProjectCloseButton)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
    }
}

// MARK: - Row views

private struct LiveSessionRow: View {
    @ObservedObject var session: LiveSession
    @ObservedObject var appState: AppState
    let isActive: Bool

    init(session: LiveSession, isActive: Bool) {
        self.session = session
        self.appState = session.appState
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)
                if appState.toolActivityState != .idle {
                    Circle()
                        .fill(.purple)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
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
                .foregroundStyle(dimmed ? .accessibleSecondary : .primary)
                .lineLimit(1)
            Spacer()
            Text(RelativeTimestampFormatter.string(from: session.updatedAt))
                .font(.system(size: 10))
                .foregroundStyle(.primary)
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
            .foregroundStyle(.accessibleSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}
