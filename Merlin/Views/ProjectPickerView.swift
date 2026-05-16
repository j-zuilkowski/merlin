import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectPickerView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// When provided the picker runs as a sheet: selecting a project calls this
    /// closure and dismisses instead of opening a new window.
    var onSelect: ((ProjectRef) -> Void)? = nil

    @State private var selected: ProjectRef?
    @State private var isShowingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merlin")
                        .font(.title2.bold())
                    Text(onSelect == nil
                         ? "Open a project to start a session"
                         : "Choose a project to add to this workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            if recents.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No recent projects")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Projects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(recents.projects) { ref in
                            ProjectRowView(ref: ref, isSelected: selected?.path == ref.path)
                                .onTapGesture { selected = ref }
                                .onTapGesture(count: 2) { open(ref) }
                                .contextMenu {
                                    Button("Remove from Recents") {
                                        if selected?.path == ref.path { selected = nil }
                                        recents.remove(ref)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            HStack {
                Button("Clear Recents") { recents.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.projectPickerClearRecentsButton)
                Spacer()
                if onSelect != nil {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.projectPickerCancelButton)
                }
                Button("Open Folder…") { isShowingFilePicker = true }
                    .accessibilityIdentifier(AccessibilityID.projectPickerOpenFolderButton)
                Button(onSelect == nil ? "Open" : "Add to Workspace") {
                    if let s = selected { open(s) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
                .accessibilityIdentifier(AccessibilityID.projectPickerOpenButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 380)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                open(.make(url: url))
            }
        }
    }

    private func open(_ ref: ProjectRef) {
        recents.touch(ref)
        if let onSelect {
            onSelect(ref)
            dismiss()
        } else {
            NSApp.keyWindow?.close()
            openWindow(value: ref)
        }
    }
}

private struct ProjectRowView: View {
    let ref: ProjectRef
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayName)
                    .font(.body.weight(.medium))
                Text(ref.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ref.lastOpenedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
