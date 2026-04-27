import AppKit
import Combine
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ChatEntryRow(
                                item: item,
                                onToggleThinking: item.role == .assistant ? {
                                    model.toggleThinkingExpansion(at: index)
                                } : nil,
                                onToggleTool: item.role == .tool ? {
                                    model.toggleToolExpansion(at: index)
                                } : nil
                            )
                            .id(item.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.revision) { _, _ in
                    guard let last = model.items.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            inputBar
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onReceive(NotificationCenter.default.publisher(for: .merlinNewSession)) { _ in
            model.clear()
        }
    }

    private var header: some View {
        HStack {
            ProviderHUD()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                )
                .accessibilityIdentifier("chat-input")
                .disabled(model.isSending)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                if model.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(.thinMaterial)
    }

    private func sendMessage() {
        Task { @MainActor in
            await model.submit(appState: appState)
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var items: [ChatEntry] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var revision: Int = 0

    private var assistantIndex: Int?
    private var toolIndexByCallID: [String: Int] = [:]

    func submit(appState: AppState) async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false, isSending == false else {
            return
        }

        draft = ""
        isSending = true
        assistantIndex = nil
        toolIndexByCallID.removeAll()
        appState.toolActivityState = .streaming
        appState.thinkingModeActive = appState.engine.shouldUseThinking(for: message)

        appendUser(message)

        for await event in appState.engine.send(userMessage: message) {
            switch event {
            case .text(let text):
                appendAssistantText(text)
                appState.toolActivityState = .streaming
            case .thinking(let text):
                appendThinking(text)
                appState.toolActivityState = .streaming
            case .toolCallStarted(let call):
                appState.toolActivityState = .toolExecuting
                appendToolCall(call)
            case .toolCallResult(let result):
                appState.toolActivityState = .toolExecuting
                updateToolResult(result)
            case .systemNote(let note):
                appendSystemNote(note)
            case .error(let error):
                appendError(error)
            }
        }

        isSending = false
        appState.thinkingModeActive = false
        appState.toolActivityState = .idle
    }

    func clear() {
        items.removeAll()
        isSending = false
        draft = ""
        assistantIndex = nil
        toolIndexByCallID.removeAll()
        bumpRevision()
    }

    func toggleThinkingExpansion(at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].thinkingExpanded.toggle()
        bumpRevision()
    }

    func toggleToolExpansion(at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].toolExpanded.toggle()
        bumpRevision()
    }

    private func appendUser(_ text: String) {
        items.append(ChatEntry(role: .user, text: text))
        bumpRevision()
    }

    private func appendAssistantText(_ text: String) {
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].text += text
        } else {
            items.append(ChatEntry(role: .assistant, text: text))
            assistantIndex = items.count - 1
        }
        bumpRevision()
    }

    private func appendThinking(_ text: String) {
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].thinkingText += text
        } else {
            items.append(ChatEntry(role: .assistant, text: "", thinkingText: text))
            assistantIndex = items.count - 1
        }
        bumpRevision()
    }

    private func appendToolCall(_ call: ToolCall) {
        let entry = ChatEntry(
            role: .tool,
            text: "",
            toolCallID: call.id,
            toolName: call.function.name,
            toolArguments: call.function.arguments,
            toolExpanded: true
        )
        items.append(entry)
        toolIndexByCallID[call.id] = items.count - 1
        bumpRevision()
    }

    private func updateToolResult(_ result: ToolResult) {
        guard let index = toolIndexByCallID[result.toolCallId], items.indices.contains(index) else {
            items.append(ChatEntry(
                role: .system,
                text: "Tool result for \(result.toolCallId): \(result.content)"
            ))
            bumpRevision()
            return
        }

        items[index].toolResult = result.content
        items[index].toolIsError = result.isError
        bumpRevision()
    }

    private func appendSystemNote(_ text: String) {
        items.append(ChatEntry(role: .system, text: text))
        bumpRevision()
    }

    private func appendError(_ error: Error) {
        items.append(ChatEntry(role: .error, text: String(describing: error)))
        bumpRevision()
    }

    private func bumpRevision() {
        revision &+= 1
    }
}

struct ChatEntry: Identifiable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case tool
        case system
        case error
    }

    var id = UUID()
    var role: Role
    var text: String
    var thinkingText: String = ""
    var thinkingExpanded: Bool = false
    var toolCallID: String?
    var toolName: String?
    var toolArguments: String?
    var toolResult: String?
    var toolIsError: Bool = false
    var toolExpanded: Bool = true
}

private struct ChatEntryRow: View {
    let item: ChatEntry
    let onToggleThinking: (() -> Void)?
    let onToggleTool: (() -> Void)?

    var body: some View {
        switch item.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .tool:
            toolCard
        case .system:
            systemNote
        case .error:
            errorNote
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 80)
            bubble(
                background: Color.accentColor.opacity(0.18),
                border: Color.accentColor.opacity(0.35),
                foreground: .primary,
                alignment: .trailing
            ) {
                markdownText(item.text)
            }
            .frame(maxWidth: 680, alignment: .trailing)
        }
    }

    private var assistantBubble: some View {
        HStack {
            bubble(
                background: Color(nsColor: .controlBackgroundColor),
                border: Color(nsColor: .separatorColor).opacity(0.35),
                foreground: .primary,
                alignment: .leading
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if item.text.isEmpty == false {
                        markdownText(item.text)
                    }

                    if item.thinkingText.isEmpty == false {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: { onToggleThinking?() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: item.thinkingExpanded ? "chevron.down" : "chevron.right")
                                    Text("Thinking")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            if item.thinkingExpanded {
                                Text(renderMarkdown(item.thinkingText))
                                    .font(.callout.italic())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text(item.thinkingTextPreview)
                                    .font(.callout.italic())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            Spacer(minLength: 80)
        }
    }

    private var toolCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: { onToggleTool?() }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.toolExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.toolName ?? "tool")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        Text(item.toolResult == nil ? "running" : (item.toolIsError ? "error" : "done"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.toolIsError ? .orange : .secondary)
                    }
                }
                .buttonStyle(.plain)

                if item.toolExpanded {
                    if let arguments = item.toolArguments, arguments.isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Arguments")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(arguments)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let result = item.toolResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Result")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(result)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(item.toolIsError ? .orange : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(item.toolSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var systemNote: some View {
        HStack {
            Spacer(minLength: 40)
            Text(renderMarkdown(item.text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
            Spacer(minLength: 40)
        }
    }

    private var errorNote: some View {
        HStack {
            Spacer(minLength: 40)
            Text(renderMarkdown(item.text))
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
            Spacer(minLength: 40)
        }
    }

    private func bubble<Content: View>(
        background: Color,
        border: Color,
        foreground: Color,
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.body)
            .foregroundStyle(foreground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .textSelection(.enabled)
    }

    private func markdownText(_ text: String) -> Text {
        Text(renderMarkdown(text))
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        // Two spaces before \n = hard line break in CommonMark
        let fixed = text.replacingOccurrences(of: "\n", with: "  \n")
        return (try? AttributedString(markdown: fixed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private extension ChatEntry {
    var thinkingTextPreview: String {
        let preview = thinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count <= 140 {
            return preview
        }
        return String(preview.prefix(140)) + "..."
    }

    var toolSummary: String {
        if let result = toolResult, result.isEmpty == false {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let arguments = toolArguments, arguments.isEmpty == false {
            return arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return toolName ?? "Tool"
    }
}
