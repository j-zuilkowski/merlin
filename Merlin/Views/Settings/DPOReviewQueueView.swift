import SwiftUI

@MainActor
final class DPOReviewQueueViewModel: ObservableObject {
    @Published private(set) var entries: [DPOPendingEntry] = []
    @Published private(set) var selectedEntryID: String?
    @Published private(set) var selectedPrompt: String = ""
    @Published private(set) var selectedRejected: String = ""
    @Published var chosenText: String = ""

    private let store: DPOReviewStore

    init(store: DPOReviewStore) {
        self.store = store
    }

    var canAccept: Bool {
        selectedEntryID != nil && !chosenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reload() async {
        let loaded = await store.loadPendingEntries()
        entries = loaded
        if let selectedEntryID,
           loaded.contains(where: { $0.id == selectedEntryID }) {
            select(entryID: selectedEntryID)
        } else if let first = loaded.first {
            select(entryID: first.id)
        } else {
            clearSelection()
        }
    }

    func select(entryID: String) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            clearSelection()
            return
        }
        selectedEntryID = entry.id
        selectedPrompt = entry.prompt
        selectedRejected = entry.rejected
        chosenText = entry.chosen
    }

    func acceptSelected() async throws {
        guard let selectedEntryID else { return }
        try await store.accept(entryID: selectedEntryID, chosen: chosenText)
        entries.removeAll { $0.id == selectedEntryID }
        if let next = entries.first {
            select(entryID: next.id)
        } else {
            clearSelection()
        }
    }

    func declineSelected() async throws {
        guard let selectedEntryID else { return }
        try await store.decline(entryID: selectedEntryID)
        entries.removeAll { $0.id == selectedEntryID }
        if let next = entries.first {
            select(entryID: next.id)
        } else {
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedEntryID = nil
        selectedPrompt = ""
        selectedRejected = ""
        chosenText = ""
    }
}

@MainActor
struct DPOReviewQueueView: View {
    @StateObject private var viewModel: DPOReviewQueueViewModel

    init(store: DPOReviewStore = DPOReviewStore()) {
        _viewModel = StateObject(wrappedValue: DPOReviewQueueViewModel(store: store))
    }

    var body: some View {
        GroupBox("Review Queue") {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.entries.isEmpty {
                    Text("No pending DPO review entries.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        queueList
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                        detailPane
                    }
                }
            }
            .padding(.top, 8)
            .task {
                await viewModel.reload()
            }
        }
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.entries) { entry in
                    Button {
                        viewModel.select(entryID: entry.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.prompt)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(entry.modelID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(viewModel.selectedEntryID == entry.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(maxHeight: 260)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                Text("Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedPrompt.isEmpty ? "Select an entry to preview it." : viewModel.selectedPrompt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Rejected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedRejected.isEmpty ? " " : viewModel.selectedRejected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Chosen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.chosenText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button("Accept") {
                    Task { try? await viewModel.acceptSelected() }
                }
                .disabled(!viewModel.canAccept)

                Button("Accept + Edit") {
                    Task { try? await viewModel.acceptSelected() }
                }
                .disabled(!viewModel.canAccept)

                Button("Decline", role: .destructive) {
                    Task { try? await viewModel.declineSelected() }
                }
                .disabled(viewModel.selectedEntryID == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
