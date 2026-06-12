import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI

enum ChatAccessibilityScope {
    case main
    case side

    var attachmentButtonID: String {
        switch self {
        case .main: AccessibilityID.chatAttachmentButton
        case .side: AccessibilityID.sideChatAttachmentButton
        }
    }

    var inputID: String {
        switch self {
        case .main: AccessibilityID.chatInput
        case .side: AccessibilityID.sideChatInput
        }
    }

    var voiceButtonID: String {
        switch self {
        case .main: AccessibilityID.chatVoiceButton
        case .side: AccessibilityID.sideChatVoiceButton
        }
    }

    var sendButtonID: String {
        switch self {
        case .main: AccessibilityID.chatSendButton
        case .side: AccessibilityID.sideChatSendButton
        }
    }

    var cancelButtonID: String {
        switch self {
        case .main: AccessibilityID.chatCancelButton
        case .side: AccessibilityID.sideChatCancelButton
        }
    }
}

struct ChatView: View {
    private struct PendingDomainActivation: Equatable {
        var message: String
        var suggestion: DomainActivationSuggestion
    }

    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var skillsRegistry: SkillsRegistry
    @FocusedObject private var sessionManager: SessionManager?
    @EnvironmentObject private var model: ChatViewModel
    @State private var atSuggestions: [String] = []
    @State private var showAtPicker: Bool = false
    @State private var skillQuery: String = ""
    @State private var showSkillsPicker: Bool = false
    @State private var atSuggestionTask: Task<Void, Never>? = nil
    @State private var isDragTargeted: Bool = false
    @State private var autoScrollEnabled: Bool = true
    @State private var scrollLockVisible: Bool = false
    @State private var scrollTaskIsUser: Bool = false
    @State private var shouldResumeScroll: Bool = false
    @State private var showBtwOverlay: Bool = false
    @State private var btwPrefill: String = ""
    @State private var pendingDomainActivation: PendingDomainActivation?
    @State private var pendingInjectMessage: String?

    private let accessibilityScope: ChatAccessibilityScope

    init(accessibilityScope: ChatAccessibilityScope = .main) {
        self.accessibilityScope = accessibilityScope
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            messageList

            if toolbarActionsList.isEmpty == false {
                toolbarActionsBar
                Divider()
            } else {
                Divider()
            }

            if let pendingDomainActivation {
                domainActivationBar(pendingDomainActivation)
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
        .overlay(alignment: .topTrailing) {
            PendingAttentionPanelView(
                viewModel: appState.pendingAttention,
                projectPath: appState.projectPath
            )
            .padding(.top, 56)
            .padding(.trailing, 12)
        }
        .onReceive(NotificationCenter.default.publisher(for: .merlinNewSession)) { _ in
            model.clear()
            autoScrollEnabled = true
            scrollLockVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .merlinInjectMessage)) { note in
            guard let msg = note.userInfo?["message"] as? String, !msg.isEmpty else { return }
            guard model.isSending == false else {
                pendingInjectMessage = msg
                return
            }
            model.draft = msg
            // Route through sendMessage so slash commands like /calibrate are handled.
            sendMessage()
        }
        .onChange(of: model.isSending) { _, isSending in
            guard isSending == false, let pending = pendingInjectMessage else { return }
            pendingInjectMessage = nil
            model.draft = pending
            sendMessage()
        }
        .overlay {
            if showBtwOverlay {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showBtwOverlay = false }

                    BtwOverlayView(
                        prefill: btwPrefill,
                        provider: appState.provider(for: appState.activeProviderID) ?? NullProvider(),
                        onDismiss: { showBtwOverlay = false }
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.18), value: showBtwOverlay)
    }

    private func domainActivationBar(_ pending: PendingDomainActivation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Switch to \(pending.suggestion.displayName)?")
                    .font(.callout.weight(.semibold))
                Text(pending.suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") {
                pendingDomainActivation = nil
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(AccessibilityID.chatDomainActivationCancelButton)

            Button("Send Without Switching") {
                pendingDomainActivation = nil
                submitPreparedMessage(pending.message)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(AccessibilityID.chatDomainActivationStayButton)

            Button("Switch and Send") {
                pendingDomainActivation = nil
                Task { @MainActor in
                    await appState.setActiveDomains([pending.suggestion.domainID], persistAsDefault: false)
                    submitPreparedMessage(pending.message)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.chatDomainActivationSwitchButton)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
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
                .accessibilityIdentifier(AccessibilityID.chatStopButton)
                .transition(.scale.combined(with: .opacity))
            }

            PendingAttentionChipView(viewModel: appState.pendingAttention)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
        .animation(.easeInOut(duration: 0.15), value: appState.engine.isRunning)
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
                    .accessibilityIdentifier(AccessibilityID.chatToolbarActionPrefix + action.id.uuidString)
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
            .accessibilityLabel("Attach files")
            .accessibilityIdentifier(accessibilityScope.attachmentButtonID)

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
                .accessibilityIdentifier(accessibilityScope.inputID)
                .accessibilityLabel("Message")
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
                    .accessibilityIdentifier(AccessibilityID.chatAtMentionPicker)
                }
                .popover(isPresented: $showSkillsPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    SkillsPicker(
                        query: $skillQuery,
                        onSelect: { skill in
                            insertSelectedSkill(skill)
                        },
                        onSelectBuiltin: { cmd in
                            insertSelectedBuiltin(cmd)
                        }
                    )
                    .environmentObject(skillsRegistry)
                    .padding(10)
                    .accessibilityIdentifier(AccessibilityID.chatSkillsPicker)
                }

            VoiceDictationButton(draft: $model.draft)
                .disabled(model.isSending)
                .accessibilityIdentifier(accessibilityScope.voiceButtonID)

            Button {
                if model.isSending {
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.chatCancelButton)
                    appState.stopEngine()
                } else {
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.chatSendButton)
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
            .accessibilityLabel(model.isSending ? "Stop generating" : "Send message")
            .accessibilityIdentifier(model.isSending ? accessibilityScope.cancelButtonID : accessibilityScope.sendButtonID)
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

    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        messageList
    }

    @ViewBuilder
    private var messageList: some View {
        ConversationWebView(
            entries: model.items,
            onToggleThinking: { id in
                if let index = model.items.firstIndex(where: { $0.id == id }) {
                    model.toggleThinkingExpansion(at: index)
                }
            },
            onToggleTool: { toolCallID in
                model.toggleToolExpansion(toolCallID: toolCallID)
            },
            onScrollLockChange: { locked in
                autoScrollEnabled = !locked
                scrollLockVisible = locked
            },
            shouldResumeScroll: $shouldResumeScroll
        )
        .id(model.revision)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if scrollLockVisible {
                ScrollViewReader { proxy in
                    scrollLockBanner(proxy: proxy)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func sendMessage() {
        let message = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if handleSlashCommandIfNeeded(message) {
            model.draft = ""
            return
        }
        if let suggestion = appState.suggestedDomainActivation(for: message) {
            pendingDomainActivation = PendingDomainActivation(
                message: message,
                suggestion: suggestion
            )
            return
        }
        submitPreparedMessage(message)
    }

    private func submitPreparedMessage(_ message: String) {
        model.draft = message
        // Always re-enable auto-scroll when the user sends a new message so a
        // previously locked view tracks the incoming response from the start.
        autoScrollEnabled = true
        scrollLockVisible = false
        shouldResumeScroll = true
        Task { @MainActor in
            await model.submit(appState: appState)
        }
    }

    private func handleSlashCommandIfNeeded(_ message: String) -> Bool {
        let handler = SlashCommandHandler(
            onCompact: { [appState] in
                appState.engine.contextManager.forceCompaction()
                appState.engine.emitSystemNote("[context compacted on demand]")
            },
            onCalibrate: { [appState] in
                // When slot assignments are configured, calibrate the execute-slot provider
                // (typically a local model) against a remote reference. This lets /calibrate
                // compare LM Studio models even when deepseek is the primary provider.
                let localProviderID: String
                let localModelID: String
                if let executeID = appState.engine.slotAssignments[.execute], !executeID.isEmpty {
                    localProviderID = executeID
                    localModelID = executeID.contains(":") ?
                        String(executeID.split(separator: ":", maxSplits: 1).last ?? Substring(executeID)) :
                        appState.activeModelID
                } else {
                    localProviderID = appState.activeLocalProviderID ?? appState.registry.activeProviderID
                    localModelID = appState.activeModelID
                }
                appState.calibrationCoordinator.begin(
                    localProviderID: localProviderID,
                    localModelID: localModelID
                )
            }
        )

        if handler.handle(message) == .consumed {
            return true
        }

        guard message.hasPrefix("/") else { return false }
        let parts = message.dropFirst().split(whereSeparator: \.isWhitespace)
        let command = parts.first.map(String.init)?.lowercased() ?? ""

        switch command {
        case "rewind":
            let (stepsBack, valid) = RewindCommand.parse(message)
            guard valid else {
                appState.engine.emitSystemNote("[/rewind] invalid argument — use /rewind or /rewind N (N ≥ 1)")
                return true
            }

            guard let messages = appState.engine.checkpointStore.restore(stepsBack: stepsBack) else {
                appState.engine.emitSystemNote(
                    "[/rewind] no checkpoint at \(stepsBack) step(s) back — " +
                    "\(appState.engine.checkpointStore.checkpoints.count) checkpoint(s) available"
                )
                return true
            }

            appState.engine.contextManager.clear()
            appState.engine.contextManager.load(messages)
            model.load(from: messages)
            appState.engine.checkpointStore.clear()
            appState.engine.emitSystemNote(
                "[rewound \(stepsBack) step(s) — \(messages.count) message(s) restored]"
            )
            return true

        case "btw":
            let prefill = message.dropFirst(4).trimmingCharacters(in: .whitespaces)
            btwPrefill = String(prefill)
            showBtwOverlay = true
            return true

        default:
            return false
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
        guard query.count >= 2 else {   // require at least 2 chars before scanning
            showAtPicker = false
            atSuggestions = []
            return
        }

        // Cancel any in-flight search and run the new one off the main thread.
        atSuggestionTask?.cancel()
        let projectPath = appState.projectPath
        atSuggestionTask = Task {
            let results = await Task.detached(priority: .userInitiated) {
                Self.findFiles(matching: query, in: projectPath)
            }.value
            guard !Task.isCancelled else { return }
            atSuggestions = results
            showAtPicker = !results.isEmpty
        }
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

    /// Directories to skip during @-mention file search. These are build artifact and
    /// dependency directories that are large and never contain source files the user
    /// would want to @-mention.
    nonisolated private static let findFilesSkippedDirs: Set<String> = [
        "target", ".build", "DerivedData", "node_modules", ".git",
        ".svn", "__pycache__", ".tox", "venv", ".venv", "dist", "build",
    ]

    nonisolated private static func findFiles(matching query: String, in projectPath: String) -> [String] {
        guard !projectPath.isEmpty, let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let lowerQuery = query.lowercased()
        var results: [String] = []
        for case let url as URL in enumerator {
            // Skip known large artifact directories entirely.
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if Self.findFilesSkippedDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
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

    /// Picker-tap callback for built-in slash commands. Replaces the draft
    /// with `/<name>` (no args) and dismisses the popover; the user can then
    /// type any arguments and hit Return to dispatch.
    private func insertSelectedBuiltin(_ cmd: BuiltinSlashCommand) {
        model.draft = "/\(cmd.name)"
        skillQuery = ""
        showSkillsPicker = false
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

    private func scrollLockBanner(proxy _: ScrollViewProxy) -> some View {
        HStack {
            Label("Scrolled up — new output continuing below", systemImage: "arrow.up")
                .font(.caption)
                .foregroundStyle(.accessibleSecondary)
            Spacer()
            Button("Resume ↓") {
                autoScrollEnabled = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollLockVisible = false
                }
                shouldResumeScroll = true
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier(AccessibilityID.chatResumeScrollButton)
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

    weak var subagentSidebar: SubagentSidebarViewModel?
    var subagentVMs: [UUID: SubagentBlockViewModel] = [:]
    private var assistantIndex: Int?
    private(set) var lastRAGSources: [RAGChunk] = []
    private(set) var lastGroundingReport: GroundingReport?
    private var pendingStreamingRevision: Bool = false
    private var streamingRevisionTask: Task<Void, Never>?
    private static let streamingRevisionThrottleNanoseconds: UInt64 = 75_000_000

    func submit(appState: AppState) async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false, isSending == false else {
            return
        }

        draft = ""
        isSending = true
        assistantIndex = nil
        lastRAGSources = []
        lastGroundingReport = nil
        appState.toolActivityState = .streaming
        appState.thinkingModeActive = appState.engine.shouldUseThinking(for: message)

        let resolved = ContextInjector.resolveAtMentions(in: message, projectPath: appState.projectPath)
        var turnFailed = false
        appendUser(resolved)
        persistTranscript(appState: appState)

        await appState.awaitRuntimePluginsReady()

        for await event in appState.engine.send(userMessage: resolved) {
            switch event {
            case .text(let text):
                appendAssistantText(text)
                appState.toolActivityState = .streaming
            case .thinking(let text):
                appendThinking(text)
                appState.toolActivityState = .streaming
            case .slotRuntimeState(let slot, let state):
                await appState.publishSlotRuntimeState(state, for: slot)
            case .toolCallStarted:
                appState.toolActivityState = .toolExecuting
                applyEngineEvent(event)
            case .toolCallResult:
                appState.toolActivityState = .toolExecuting
                applyEngineEvent(event)
            case .ragSources(let chunks):
                lastRAGSources = chunks
                if let index = assistantIndex, items.indices.contains(index) {
                    items[index].ragSources = chunks
                    bumpRevision()
                }
            case .groundingReport(let report):
                applyGroundingReport(report)
            case .subagentStarted, .subagentUpdate:
                applyEngineEvent(event)
            case .systemNote(let note):
                appendSystemNote(note)
            case .cleanStop(let reason, let summary):
                appendSystemNote("⛔ Cannot continue: \(reason). \(summary)")
            case .error(let error):
                turnFailed = true
                appendError(error)
            }
        }

        isSending = false
        appState.thinkingModeActive = false
        appState.toolActivityState = .idle
        flushPendingStreamingRevision()
        let finalSlotState: SlotRuntimeState = turnFailed ? .error : .ready
        for (slot, state) in appState.slotRuntimeStates where state == .busy {
            await appState.publishSlotRuntimeState(finalSlotState, for: slot)
        }
        persistTranscript(appState: appState)
    }

    func clear() {
        items.removeAll()
        isSending = false
        draft = ""
        assistantIndex = nil
        lastRAGSources = []
        lastGroundingReport = nil
        subagentVMs.removeAll()
        bumpRevision()
    }

    /// Populates items from a stored message history (e.g. after restoring a session).
    /// Tool calls from assistant messages are nested as ToolCallEntry values on the
    /// assistant ChatEntry rather than appearing as separate items. Multiple rounds of
    /// tool calls within a single LLM response are merged into ONE ChatEntry so the
    /// UI shows one bubble (matching the streaming path behaviour).
    func load(from messages: [Message]) {
        items = []
        lastGroundingReport = nil
        // Pending tool calls accumulate across back-to-back assistant+tool round-trips.
        // They are merged into the first assistant message that carries text, producing
        // one bubble per logical LLM response regardless of how many tool-call rounds occurred.
        var pendingToolCalls: [ToolCallEntry] = []

        func flushOrphanedTools() {
            guard !pendingToolCalls.isEmpty else { return }
            var entry = ChatEntry(role: .assistant, text: "")
            entry.toolCalls = pendingToolCalls
            items.append(entry)
            pendingToolCalls = []
        }

        for message in messages {
            switch message.role {
            case .system:
                let text = message.content.plainText
                guard !text.isEmpty else { continue }
                items.append(ChatEntry(role: .system, text: text))

            case .user:
                // Flush any orphaned tool calls before the next user turn
                flushOrphanedTools()
                let text = message.content.plainText
                guard !text.isEmpty else { continue }
                items.append(ChatEntry(role: .user, text: text))

            case .assistant:
                if let calls = message.toolCalls, !calls.isEmpty {
                    // Accumulate tool calls without flushing — they will be merged
                    // into the subsequent text-bearing assistant message.
                    for call in calls {
                        pendingToolCalls.append(ToolCallEntry(
                            id: call.id,
                            name: call.function.name,
                            arguments: call.function.arguments
                        ))
                    }
                } else {
                    // Text response: merge pending tool calls into this ONE entry.
                    let text = message.content.plainText
                    var entry = ChatEntry(role: .assistant, text: text)
                    entry.thinkingText = message.thinkingContent ?? ""
                    entry.toolCalls = pendingToolCalls
                    pendingToolCalls = []
                    if !text.isEmpty || !entry.toolCalls.isEmpty {
                        items.append(entry)
                    }
                }

            case .tool:
                if let callID = message.toolCallId,
                   let j = pendingToolCalls.firstIndex(where: { $0.id == callID }) {
                    pendingToolCalls[j].result = message.content.plainText
                }
            }
        }
        // Flush any remaining tool calls if the conversation ended mid-loop
        flushOrphanedTools()
        bumpRevision()
    }

    private func persistTranscript(appState: AppState) {
        guard let store = appState.sessionStore,
              let sessionID = appState.engine.sessionID ?? store.activeSessionID
        else { return }

        let existing = store.sessions.first(where: { $0.id == sessionID })
        var updated = existing ?? Session(
            id: sessionID,
            title: "New Session",
            messages: [],
            activeDomainIDs: appState.engine.activeDomainIDs
        )
        let messages = messagesForPersistence()
        updated.messages = messages
        updated.title = Session.generateTitle(from: messages)
        updated.updatedAt = Date()
        updated.activeDomainIDs = appState.engine.activeDomainIDs
        try? store.save(updated)
    }

    private func messagesForPersistence() -> [Message] {
        var messages: [Message] = []
        for item in items {
            switch item.role {
            case .user:
                messages.append(Message(
                    role: .user,
                    content: .text(item.text),
                    timestamp: Date()
                ))
            case .assistant:
                let toolCalls = item.toolCalls.map { toolCall in
                    ToolCall(
                        id: toolCall.id,
                        type: "function",
                        function: FunctionCall(name: toolCall.name, arguments: toolCall.arguments)
                    )
                }
                if !item.text.isEmpty || !item.thinkingText.isEmpty || !toolCalls.isEmpty {
                    messages.append(Message(
                        role: .assistant,
                        content: .text(item.text),
                        toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                        thinkingContent: item.thinkingText.isEmpty ? nil : item.thinkingText,
                        timestamp: Date()
                    ))
                }
                for toolCall in item.toolCalls {
                    guard let result = toolCall.result else { continue }
                    messages.append(Message(
                        role: .tool,
                        content: .text(result),
                        toolCallId: toolCall.id,
                        timestamp: Date()
                    ))
                }
            case .system:
                guard !item.text.isEmpty else { continue }
                messages.append(Message(
                    role: .system,
                    content: .text(item.text),
                    timestamp: Date()
                ))
            case .error:
                guard !item.text.isEmpty else { continue }
                messages.append(Message(
                    role: .system,
                    content: .text("[error] \(item.text)"),
                    timestamp: Date()
                ))
            }
        }
        return messages
    }

    func toggleThinkingExpansion(at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].thinkingExpanded.toggle()
        bumpRevision()
    }

    func toggleToolExpansion(toolCallID: String) {
        for i in items.indices {
            if let j = items[i].toolCalls.firstIndex(where: { $0.id == toolCallID }) {
                // expansion state is managed purely in JS DOM; nothing to update in model
                _ = (i, j)
                return
            }
        }
    }

    func applyEngineEvent(_ event: AgentEvent) {
        switch event {
        case .slotRuntimeState:
            break
        case .toolCallStarted(let call):
            appendToolCall(call)
        case .toolCallResult(let result):
            updateToolResult(result)
        case .subagentStarted(let id, let agentName):
            let vm = SubagentBlockViewModel(agentName: agentName)
            subagentVMs[id] = vm
            var entry = ChatEntry(role: .assistant, text: "")
            entry.subagentID = id
            entry.subagentBlock = SubagentBlock(
                agentName: agentName,
                status: "running",
                tools: [],
                summary: nil,
                text: ""
            )
            items.append(entry)
            if let sidebar = subagentSidebar {
                sidebar.add(SubagentSidebarEntry(
                    id: id,
                    parentSessionID: sidebar.parentSessionID,
                    agentName: agentName,
                    label: agentName))
            }
            bumpRevision()
        case .subagentUpdate(let id, let subagentEvent):
            subagentVMs[id]?.apply(subagentEvent)
            if let vm = subagentVMs[id],
               let idx = items.firstIndex(where: { $0.subagentID == id }) {
                let statusString: String
                switch vm.status {
                case .running:   statusString = "running"
                case .completed: statusString = "completed"
                case .failed:    statusString = "failed"
                }
                items[idx].subagentBlock = SubagentBlock(
                    agentName: vm.agentName,
                    status: statusString,
                    tools: vm.toolEvents.map {
                        SubagentToolLine(name: $0.toolName, done: $0.status == .done)
                    },
                    summary: vm.summary,
                    text: vm.accumulatedText)
            }
            subagentSidebar?.apply(event: subagentEvent, to: id)
            bumpRevision()
            case .ragSources(let chunks):
                lastRAGSources = chunks
                if let index = assistantIndex, items.indices.contains(index) {
                    items[index].ragSources = chunks
                    bumpRevision()
                }
            case .groundingReport(let report):
                applyGroundingReport(report)
            default:
                break
        }
    }

    private func appendUser(_ text: String) {
        items.append(ChatEntry(role: .user, text: text))
        bumpRevision()
    }

    func appendAssistantText(_ text: String) {
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].text += text
            if items[index].ragSources.isEmpty {
                items[index].ragSources = lastRAGSources
            }
            if items[index].groundingReport == nil {
                items[index].groundingReport = lastGroundingReport
            }
        } else {
            var entry = ChatEntry(role: .assistant, text: text)
            entry.ragSources = lastRAGSources
            entry.groundingReport = lastGroundingReport
            items.append(entry)
            assistantIndex = items.count - 1
        }
        scheduleStreamingRevision()
    }

    private func appendThinking(_ text: String) {
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].thinkingText += text
            if items[index].ragSources.isEmpty {
                items[index].ragSources = lastRAGSources
            }
            if items[index].groundingReport == nil {
                items[index].groundingReport = lastGroundingReport
            }
        } else {
            var entry = ChatEntry(role: .assistant, text: "", thinkingText: text)
            entry.ragSources = lastRAGSources
            entry.groundingReport = lastGroundingReport
            items.append(entry)
            assistantIndex = items.count - 1
        }
        scheduleStreamingRevision()
    }

    private func appendToolCall(_ call: ToolCall) {
        let toolCall = ToolCallEntry(id: call.id, name: call.function.name, arguments: call.function.arguments)
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].toolCalls.append(toolCall)
            if items[index].groundingReport == nil {
                items[index].groundingReport = lastGroundingReport
            }
        } else {
            var entry = ChatEntry(role: .assistant, text: "")
            entry.toolCalls.append(toolCall)
            entry.groundingReport = lastGroundingReport
            items.append(entry)
            assistantIndex = items.count - 1
        }
        bumpRevision()
    }

    private func applyGroundingReport(_ report: GroundingReport) {
        lastGroundingReport = report
        if let index = assistantIndex, items.indices.contains(index) {
            items[index].groundingReport = report
        }
        bumpRevision()
    }

    private func updateToolResult(_ result: ToolResult) {
        for i in items.indices {
            if let j = items[i].toolCalls.firstIndex(where: { $0.id == result.toolCallId }) {
                items[i].toolCalls[j].result = result.content
                items[i].toolCalls[j].isError = result.isError
                bumpRevision()
                return
            }
        }
        items.append(ChatEntry(role: .system, text: "Tool result for \(result.toolCallId): \(result.content)"))
        bumpRevision()
    }

    private func appendSystemNote(_ text: String) {
        items.append(ChatEntry(role: .system, text: text))
        bumpRevision()
    }

    private func appendError(_ error: Error) {
        // ProviderError carries structured HTTP info — map to actionable messages.
        if let pe = error as? ProviderError {
            let message: String
            switch pe {
            case .httpError(let code, _, let pid):
                switch code {
                case 400:
                    message = "\(pid) rejected the request (HTTP 400 — bad request). The context may be too large. Try compacting (Session → Compact Context) and retrying."
                case 401, 403:
                    message = "API key rejected by \(pid) (HTTP \(code)). Check your key in Settings → Providers."
                case 429:
                    message = "Rate limited by \(pid). Retried but limit persisted. Try again in a moment."
                case 500...599:
                    message = "\(pid) returned HTTP \(code) after retries. The provider may be temporarily unavailable."
                default:
                    message = "\(pid) returned HTTP \(code). Try again or check the provider status."
                }
            case .networkError(_, let pid):
                message = "Network error connecting to \(pid). Check your connection and try again."
            }
            items.append(ChatEntry(role: .error, text: message))
            bumpRevision()
            return
        }

        // String(describing:) on a system URLError often produces
        // "Error Domain=NSURLErrorDomain Code=-1011 "(null)"" because the
        // NSError has no NSLocalizedDescriptionKey. Use localizedDescription
        // first; if that also comes back as "(null)" or empty, synthesise a
        // human-readable message from domain + code so the user knows what
        // went wrong (usually an API key or network issue).
        let nsError = error as NSError
        let message: String
        if nsError.domain == NSURLErrorDomain {
            // Replace generic / null system strings with actionable messages.
            switch nsError.code {
            case -1011: message = "API connection error — the server returned an unexpected response. Check your API key in Settings and try again."
            case -1009: message = "No internet connection."
            case -1001: message = "Request timed out — the server took too long to respond."
            case -1004: message = "Could not connect to the server."
            case -1005: message = "The network connection was lost."
            default:
                let raw = nsError.localizedDescription
                message = (raw.isEmpty || raw == "(null)") ? "Network error (NSURLError \(nsError.code))." : raw
            }
        } else {
            let raw = nsError.localizedDescription
            message = (raw.isEmpty || raw == "(null)") ? "Error \(nsError.domain) \(nsError.code)" : raw
        }
        items.append(ChatEntry(role: .error, text: message))
        bumpRevision()
    }

    private func bumpRevision() {
        pendingStreamingRevision = false
        streamingRevisionTask?.cancel()
        streamingRevisionTask = nil
        revision &+= 1
    }

    private func scheduleStreamingRevision() {
        pendingStreamingRevision = true
        guard streamingRevisionTask == nil else { return }
        streamingRevisionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.streamingRevisionThrottleNanoseconds)
            await MainActor.run {
                self?.flushPendingStreamingRevision()
            }
        }
    }

    private func flushPendingStreamingRevision() {
        guard pendingStreamingRevision else {
            streamingRevisionTask?.cancel()
            streamingRevisionTask = nil
            return
        }
        pendingStreamingRevision = false
        streamingRevisionTask?.cancel()
        streamingRevisionTask = nil
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
        .accessibilityLabel(engine.state == .recording ? "Stop recording" : "Dictate")
    }
}

/// A single tool call nested inside an assistant ChatEntry.
struct ToolCallEntry: Identifiable, Sendable {
    var id: String          // API tool call ID
    var name: String        // function name
    var arguments: String = ""
    var result: String?
    var isError: Bool = false
}

struct ChatEntry: Identifiable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system
        case error
    }

    var id = UUID()
    var role: Role
    var text: String
    var thinkingText: String = ""
    var thinkingExpanded: Bool = false
    var toolCalls: [ToolCallEntry] = []   // nested tool calls for assistant entries
    var subagentID: UUID? = nil
    var subagentBlock: SubagentBlock? = nil
    var ragSources: [RAGChunk] = []
    var groundingReport: GroundingReport? = nil
}
