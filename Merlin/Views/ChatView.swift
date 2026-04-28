import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var skillsRegistry: SkillsRegistry
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var model = ChatViewModel()
    @State private var atSuggestions: [String] = []
    @State private var showAtPicker: Bool = false
    @State private var skillQuery: String = ""
    @State private var showSkillsPicker: Bool = false
    @State private var isDragTargeted: Bool = false
    @State private var autoScrollEnabled: Bool = true
    @State private var scrollLockVisible: Bool = false
    @State private var isProgrammaticallyScrolling: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    scrollContent(proxy: proxy)

                    if scrollLockVisible {
                        scrollLockBanner(proxy: proxy)
                    }
                }
            }

            if toolbarActionsList.isEmpty == false {
                toolbarActionsBar
                Divider()
            } else {
                Divider()
            }

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
            autoScrollEnabled = true
            scrollLockVisible = false
        }
    }

    private var header: some View {
        HStack {
            if appState.engine.isRunning {
                Button {
                    appState.stopEngine()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .padding(5)
                        .background(.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .help("Stop (⌘.)")
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                if let session = sessionManager.activeSession {
                    session.permissionMode = session.permissionMode.next
                }
            } label: {
                Text(currentMode.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(currentMode.color.opacity(0.12))
                    .foregroundStyle(currentMode.color)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help("Cycle permission mode (⌘⇧M)")

            ProviderHUD()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
        .animation(.easeInOut(duration: 0.15), value: appState.engine.isRunning)
    }

    private var currentMode: PermissionMode {
        sessionManager.activeSession?.permissionMode ?? .ask
    }

    private var toolbarActionsList: [ToolbarAction] {
        appState.toolbarActionsList
    }

    private var toolbarActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(toolbarActionsList, id: \.id) { action in
                    Button(action.label) {
                        Task {
                            guard let result = try? await action.run() else { return }
                            for await _ in appState.engine.send(
                                userMessage: "[Toolbar] \(action.label): \(result)"
                            ) {}
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(height: toolbarActionsList.isEmpty ? 0 : 36)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                openAttachmentPanel()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .help("Attach files")
            .disabled(model.isSending)

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
                .onChange(of: model.draft) { _, draft in
                    updateAtSuggestions(for: draft)
                    updateSkillSuggestions(for: draft)
                }
                .popover(isPresented: $showAtPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    AtMentionPicker(suggestions: atSuggestions) { filename in
                        if let atIdx = model.draft.lastIndex(of: "@") {
                            model.draft = String(model.draft[..<atIdx]) + "@" + filename + " "
                        }
                        showAtPicker = false
                    }
                    .padding(10)
                }
                .popover(isPresented: $showSkillsPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    SkillsPicker(query: $skillQuery) { skill in
                        insertSelectedSkill(skill)
                    }
                    .environmentObject(skillsRegistry)
                    .padding(10)
                }

            VoiceDictationButton(draft: $model.draft)
                .disabled(model.isSending)

            Button {
                if model.isSending {
                    appState.stopEngine()
                } else {
                    sendMessage()
                }
            } label: {
                if model.isSending {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isSending ? .red : .accentColor)
            .disabled(!model.isSending && model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(.thinMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            handleDroppedProviders(providers)
        }
    }

    @ViewBuilder
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        if #available(macOS 15.0, *) {
            ScrollView {
                messageList
            }
            .onScrollGeometryChange(for: Double.self) { geo in
                geo.contentSize.height - geo.containerSize.height - geo.contentOffset.y
            } action: { _, distanceFromBottom in
                guard !isProgrammaticallyScrolling else { return }
                let shouldAutoScroll = distanceFromBottom < 40
                if shouldAutoScroll != autoScrollEnabled {
                    autoScrollEnabled = shouldAutoScroll
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollLockVisible = !shouldAutoScroll
                    }
                }
            }
            .onChange(of: model.revision) { _, _ in
                guard autoScrollEnabled else { return }
                isProgrammaticallyScrolling = true
                proxy.scrollTo("bottom", anchor: .bottom)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isProgrammaticallyScrolling = false
                }
            }
        } else {
            ScrollView {
                messageList
            }
            .onChange(of: model.revision) { _, _ in
                guard autoScrollEnabled else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var messageList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                if let subagentID = item.subagentID,
                   let subagentVM = model.subagentVMs[subagentID] {
                    SubagentBlockView(vm: subagentVM)
                        .id(item.id)
                } else {
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

            Color.clear
                .frame(height: 1)
                .id("bottom")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sendMessage() {
        Task { @MainActor in
            await model.submit(appState: appState)
        }
    }

    private func updateAtSuggestions(for draft: String) {
        guard let atIdx = draft.lastIndex(of: "@") else {
            showAtPicker = false
            atSuggestions = []
            return
        }

        let query = String(draft[draft.index(after: atIdx)...])
            .components(separatedBy: .whitespaces)
            .first ?? ""
        guard !query.isEmpty else {
            showAtPicker = false
            atSuggestions = []
            return
        }

        atSuggestions = findFiles(matching: query, in: appState.projectPath)
        showAtPicker = !atSuggestions.isEmpty
    }

    private func updateSkillSuggestions(for draft: String) {
        guard draft.hasPrefix("/") else {
            showSkillsPicker = false
            skillQuery = ""
            return
        }

        let remainder = draft.dropFirst()
        skillQuery = String(remainder.prefix { !$0.isWhitespace })
        showSkillsPicker = true
    }

    private func findFiles(matching query: String, in projectPath: String) -> [String] {
        guard !projectPath.isEmpty, let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let lowerQuery = query.lowercased()
        var results: [String] = []
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: projectPath + "/", with: "")
            let name = url.lastPathComponent.lowercased()
            if name.contains(lowerQuery) || relative.lowercased().contains(lowerQuery) {
                results.append(relative)
                if results.count == 10 { break }
            }
        }
        return results
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if let block = try? await ContextInjector.inlineAttachment(url: url) {
                            model.draft += "\n\(block)"
                        }
                    }
                }
            }
        }
    }

    private func insertSelectedSkill(_ skill: Skill) {
        let rendered = skillsRegistry.render(skill: skill, arguments: "")
        if model.draft.hasPrefix("/") {
            let remainder = model.draft.dropFirst()
            let suffixIndex = remainder.firstIndex(where: { $0.isWhitespace }) ?? remainder.endIndex
            let suffix = remainder[suffixIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            model.draft = rendered + (suffix.isEmpty ? "" : " \(suffix)")
        } else {
            model.draft = rendered
        }
        skillQuery = ""
        showSkillsPicker = false
    }

    private func openAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                Task {
                    if let block = try? await ContextInjector.inlineAttachment(url: url) {
                        await MainActor.run { model.draft += "\n\(block)" }
                    }
                }
            }
        }
    }

    private func scrollLockBanner(proxy: ScrollViewProxy) -> some View {
        HStack {
            Label("Scrolled up — new output continuing below", systemImage: "arrow.up")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Resume ↓") {
                autoScrollEnabled = true
                isProgrammaticallyScrolling = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollLockVisible = false
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isProgrammaticallyScrolling = false
                }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var items: [ChatEntry] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var revision: Int = 0

    var subagentVMs: [UUID: SubagentBlockViewModel] = [:]
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

        let resolved = ContextInjector.resolveAtMentions(in: message, projectPath: appState.projectPath)
        appendUser(resolved)

        for await event in appState.engine.send(userMessage: resolved) {
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
            case .subagentStarted, .subagentUpdate:
                applyEngineEvent(event)
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
        subagentVMs.removeAll()
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

    func applyEngineEvent(_ event: AgentEvent) {
        switch event {
        case .subagentStarted(let id, let agentName):
            let vm = SubagentBlockViewModel(agentName: agentName)
            subagentVMs[id] = vm
            var entry = ChatEntry(role: .assistant, text: "")
            entry.subagentID = id
            items.append(entry)
            bumpRevision()
        case .subagentUpdate(let id, let subagentEvent):
            subagentVMs[id]?.apply(subagentEvent)
            bumpRevision()
        default:
            break
        }
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

private struct VoiceDictationButton: View {
    @Binding var draft: String
    @StateObject private var engine = VoiceDictationEngine.shared

    var body: some View {
        Button {
            Task {
                await engine.setOnTranscript { [weak engine] text in
                    Task { @MainActor in
                        draft += (draft.isEmpty ? "" : " ") + text
                        if engine?.state == .recording {
                            await engine?.stop()
                        }
                    }
                }
                await engine.toggle()
            }
        } label: {
            Image(systemName: engine.state == .recording ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(engine.state == .recording ? .red : .primary)
        }
        .buttonStyle(.bordered)
        .help(engine.state == .recording ? "Stop recording" : "Dictate")
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
    var subagentID: UUID? = nil
}

private struct ChatEntryRow: View {
    let item: ChatEntry
    let onToggleThinking: (() -> Void)?
    let onToggleTool: (() -> Void)?
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        content
            .padding(.vertical, settings.messageDensity.verticalPadding)
    }

    @ViewBuilder
    private var content: some View {
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
            Spacer(minLength: 40)
            bubble(
                background: Color.accentColor.opacity(0.18),
                border: Color.accentColor.opacity(0.35),
                foreground: .primary,
                alignment: .trailing
            ) {
                markdownText(item.text)
            }
            .frame(maxWidth: 600, alignment: .trailing)
        }
        .padding(.trailing, 4)
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
