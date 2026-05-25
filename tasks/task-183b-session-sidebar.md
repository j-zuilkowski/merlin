# Task 183b — Session Sidebar Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 183a complete: SessionSidebarHelpersTests committed (failing).

---

## Write to: Merlin/Support/RelativeTimestampFormatter.swift

```swift
import Foundation

enum RelativeTimestampFormatter {
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        switch interval {
        case ..<60:      return "now"
        case ..<3600:    return "\(Int(interval / 60))m"
        case ..<86400:   return "\(Int(interval / 3600))h"
        case ..<604800:  return "\(Int(interval / 86400))d"
        default:         return "\(Int(interval / 604800))w"
        }
    }
}
```

---

## Edit: Merlin/Views/SessionSidebar.swift

Full replacement — adds "Prior Sessions" section with timestamps, archived collapse,
and context menus for resume / archive / recall / delete:

```swift
import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var mgr: SessionManager

    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            // Project header
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

                    // MARK: Active live sessions
                    SectionLabel("Sessions")

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

                    // MARK: Prior sessions (disk, not currently live)
                    let liveIDs = Set(mgr.liveSessions.map(\.id))
                    let prior = mgr.sessionStore.activeSessions
                        .filter { !liveIDs.contains($0.id) }

                    if !prior.isEmpty {
                        SectionLabel("Prior Sessions")
                            .padding(.top, 8)

                        ForEach(prior) { session in
                            PriorSessionRowView(session: session)
                                .onTapGesture {
                                    Task { await mgr.restore(session: session) }
                                }
                                .contextMenu {
                                    Button("Resume") {
                                        Task { await mgr.restore(session: session) }
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

                    // MARK: Archived sessions (collapsible)
                    let archived = mgr.sessionStore.archivedSessions
                    if !archived.isEmpty {
                        Button {
                            showArchived.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showArchived
                                      ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("Show archived")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        }
                        .buttonStyle(.plain)

                        if showArchived {
                            ForEach(archived) { session in
                                PriorSessionRowView(session: session, dimmed: true)
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
            .accessibilityIdentifier(AccessibilityID.sessionList)

            Divider()

            Button {
                TelemetryEmitter.shared.emitGUIAction("tap",
                    identifier: AccessibilityID.newSessionButton)
                Task { await mgr.newSession() }
            } label: {
                Label("New Session", systemImage: "plus")
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

// MARK: - Live session row (existing behaviour)

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

// MARK: - Disk session row (prior / archived)

private struct PriorSessionRowView: View {
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
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Section label

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

// MARK: - Permission mode badge

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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SessionSidebarHelpers.*passed|SessionSidebarHelpers.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; all SessionSidebarHelpersTests pass.

## Manual verification
```bash
pkill -x Merlin 2>/dev/null; sleep 1
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```
1. Open any project — confirm sidebar shows "Sessions" and "Prior Sessions" sections.
2. Create two sessions, close one — verify closed session appears under "Prior Sessions".
3. Right-click a prior session → Archive → confirm it disappears from Prior Sessions.
4. Click "Show archived" → verify it reappears.
5. Right-click archived → Recall → confirm it moves back to Prior Sessions.
6. Right-click prior session → Resume — confirm a new live session opens with history.
7. Timestamps should display in "Xh / Xd / Xw" format next to each prior session title.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-183b-session-sidebar.md \
        Merlin/Support/RelativeTimestampFormatter.swift \
        Merlin/Views/SessionSidebar.swift
git commit -m "Task 183b — SessionSidebar Prior Sessions + archive/recall + timestamps"
```
