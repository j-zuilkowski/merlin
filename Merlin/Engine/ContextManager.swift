// ContextManager — maintains the message history sent to the LLM on each turn.
//
// Token budget is tracked via a cheap utf8/3.5 heuristic (no tokeniser needed).
// When the estimated token count exceeds 800 000, old tool-result messages are
// collapsed to a one-line summary so the window never overflows.
// After compaction, recently-invoked skill bodies are re-injected so the model
// retains their instructions.
//
// See: Developer Manual § "Engine — ContextManager"
import Foundation

@MainActor
class ContextManager: ObservableObject {
    @Published private(set) var messages: [Message] = []
    private(set) var estimatedTokens: Int = 0
    private(set) var compactionCount: Int = 0
    private(set) var recentlyInvokedSkills: [Skill] = []
    private(set) var workingSetBudget: WorkingSetBudget = .derive(from: .conservative)

    private let compactionThreshold = 800_000
    private let compactionKeepRecentTurns = 20
    private let skillBudgetTokens = 25_000
    private let skillBudgetPerSkill = 5_000

    func append(_ message: Message) {
        messages.append(message)
        estimatedTokens = recomputeEstimatedTokens()
        if estimatedTokens >= compactionThreshold {
            compact(force: false)
        }
    }

    func clear() {
        messages.removeAll()
        estimatedTokens = 0
    }

    /// Bulk-loads historical messages (e.g. from a restored Session) and
    /// compacts immediately if the injected history exceeds the pre-run threshold.
    func load(_ messages: [Message]) {
        guard !messages.isEmpty else { return }
        for message in messages {
            self.messages.append(message)
        }
        estimatedTokens = recomputeEstimatedTokens()
        compactIfNeededBeforeRun(isContinuation: false)
    }

    func messagesForProvider() -> [Message] {
        messages
    }

    func forceCompaction() {
        compact(force: true)
    }

    /// Applies the active working-set ceilings in priority order.
    func applyWorkingSetCaps(_ caps: WorkingSetBudget) async {
        workingSetBudget = caps

        if estimatedToolBurstTokens() > caps.toolBurstCap {
            compactAfterToolBurst()
        }

        if estimatedRecentTurnTokens() > caps.recentTurnsCap {
            trimOldestRecentTurns(to: caps.recentTurnsCap)
        }

        if estimatedRAGTokens() > caps.ragInjectionCap {
            trimRAGInjection(to: caps.ragInjectionCap)
        }

        if estimatedSystemPromptTokens() > caps.systemPromptCap {
            truncateSystemPrompt(to: caps.systemPromptCap)
        }

        estimatedTokens = recomputeEstimatedTokens()
    }

    /// Token count above which `compactIfNeededBeforeRun` fires automatically.
    /// Kept well below a typical 32 K model context so the model has ample
    /// output space even in long sessions.
    let preRunCompactionThreshold = 6_000

    /// Token threshold that triggers compaction mid-loop, inside the `while true` execute loop.
    /// A `var` so tests can lower it without mocking. Default: 40 000 tokens —
    /// well below a typical 32 K model context, giving the next LLM call ample output headroom.
    var midLoopCompactionThreshold: Int = 20_000

    /// Called by `AgenticEngine.runLoop` before appending the user message.
    /// Compacts when the session has grown past `preRunCompactionThreshold` tokens
    /// and the turn is not a continuation (continuations must preserve recent
    /// tool results so the model can finish multi-step work).
    func compactIfNeededBeforeRun(isContinuation: Bool) {
        guard !isContinuation, estimatedTokens > preRunCompactionThreshold else { return }
        compact(force: true)
    }

    /// Called inside the `while true` execute loop after every tool-dispatch round.
    /// Compacts when accumulated tool results push the context past `midLoopCompactionThreshold`,
    /// keeping per-turn token cost linear regardless of how many tool iterations the loop takes.
    /// Skipped when at or below threshold — no-op cost.
    func compactIfNeededMidLoop() {
        guard estimatedTokens > midLoopCompactionThreshold else { return }
        compact(force: true)
    }

    /// Collapses the current tool-burst window when it exceeds the active
    /// working-set budget. This replaces the older global mid-loop compaction
    /// call site with a component-specific check.
    func compactAfterToolBurst() {
        let cap = workingSetBudget.toolBurstCap
        guard estimatedToolBurstTokens() > cap else { return }
        compact(force: true)
    }

    /// Mid-loop async compaction with LLM summarisation.
    ///
    /// When `estimatedTokens > midLoopCompactionThreshold`, collects the text of all removable
    /// tool-exchange groups, calls `provider` for a one-shot narrative summary (no tools,
    /// temperature 0), and compacts using that summary as the system-message digest.
    /// Falls back to the static sentinel if the provider call throws.
    /// Returns `true` when compaction fired, `false` when below threshold (no-op).
    @discardableResult
    func compactWithSummaryIfNeeded(provider: any LLMProvider) async -> Bool {
        guard estimatedTokens > midLoopCompactionThreshold else { return false }

        // Build exchange text from the same groups compact() would remove.
        let exchangeText = buildRemovableExchangeText()
        let digest: String?
        if let text = exchangeText, !text.isEmpty {
            digest = await summarise(text, using: provider)
        } else {
            digest = nil   // no removable groups → compact() will hard-truncate; digest unused
        }

        compact(force: true, customDigest: digest)
        return true
    }

    /// Extracts the text content of tool-exchange groups that `compact(force: true)` would remove.
    /// Returns nil when there are no such groups (context is pure text turns).
    private func buildRemovableExchangeText() -> String? {
        var groups: [(assistantIdx: Int, toolIndices: [Int])] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            guard msg.role == .assistant,
                  let calls = msg.toolCalls, !calls.isEmpty else { i += 1; continue }
            var toolIndices: [Int] = []
            var j = i + 1
            while j < messages.count && messages[j].role == .tool {
                toolIndices.append(j)
                j += 1
            }
            if !toolIndices.isEmpty {
                groups.append((assistantIdx: i, toolIndices: toolIndices))
            }
            i = j
        }
        guard !groups.isEmpty else { return nil }

        let recentStart = max(0, messages.count - compactionKeepRecentTurns)
        let toRemove = groups.filter { $0.assistantIdx < recentStart }.isEmpty
            ? groups
            : groups.filter { $0.assistantIdx < recentStart }

        let lines: [String] = toRemove.flatMap { group -> [String] in
            var parts: [String] = []
            // Tool names from assistant message
            if let calls = messages[group.assistantIdx].toolCalls {
                let names = calls.map { $0.function.name }.joined(separator: ", ")
                parts.append("called: \(names)")
            }
            // First 200 chars of each tool result
            for idx in group.toolIndices {
                let content: String
                switch messages[idx].content {
                case .text(let t): content = String(t.prefix(200))
                case .parts: content = "(binary)"
                }
                parts.append("result: \(content)")
            }
            return parts
        }
        return lines.joined(separator: "\n")
    }

    /// Calls `provider` once to produce a short narrative summary of `exchangeText`.
    /// Returns the provider's response text, or the raw `exchangeText` prefix as a fallback.
    private func summarise(_ exchangeText: String, using provider: any LLMProvider) async -> String {
        let systemMsg = Message(
            role: .system,
            content: .text("Summarise the following tool-call exchanges in 2–3 concise sentences. Capture what tools were called and their key results. Be specific."),
            timestamp: Date()
        )
        let userMsg = Message(
            role: .user,
            content: .text(exchangeText),
            timestamp: Date()
        )
        var request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: [systemMsg, userMsg]
        )
        request.tools = []
        request.maxTokens = 256

        do {
            let stream = try await PreflightGuard.complete(request, provider: provider)
            var result = ""
            for try await chunk in stream {
                if let text = chunk.delta?.content { result += text }
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(exchangeText.prefix(300))
                : result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return String(exchangeText.prefix(300))
        }
    }

    func recordSkillInvocation(_ skill: Skill) {
        recentlyInvokedSkills.removeAll { $0.name == skill.name }
        recentlyInvokedSkills.insert(skill, at: 0)
        if recentlyInvokedSkills.count > compactionKeepRecentTurns {
            recentlyInvokedSkills = Array(recentlyInvokedSkills.prefix(compactionKeepRecentTurns))
        }
    }

    private func recomputeEstimatedTokens() -> Int {
        messages.reduce(0) { total, message in
            total + tokenEstimate(for: message)
        }
    }

    private func estimatedSystemPromptTokens() -> Int {
        guard let index = messages.firstIndex(where: { $0.role == .system }) else { return 0 }
        return tokenEstimate(for: messages[index])
    }

    private func estimatedRAGTokens() -> Int {
        guard let firstSystemIndex = messages.firstIndex(where: { $0.role == .system }) else { return 0 }
        guard firstSystemIndex + 1 < messages.count else { return 0 }
        return messages[(firstSystemIndex + 1)...].reduce(0) { total, message in
            guard message.role == .system else { return total }
            return total + tokenEstimate(for: message)
        }
    }

    private func estimatedRecentTurnTokens() -> Int {
        messages.reduce(0) { total, message in
            switch message.role {
            case .system:
                return total
            case .user, .assistant, .tool:
                return total + tokenEstimate(for: message)
            }
        }
    }

    private func estimatedToolBurstTokens() -> Int {
        let startIndex: Int
        if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
            startIndex = lastUserIndex + 1
        } else {
            startIndex = 0
        }

        guard startIndex < messages.count else { return 0 }
        return messages[startIndex...].reduce(0) { total, message in
            switch message.role {
            case .assistant where (message.toolCalls?.isEmpty == false):
                return total + tokenEstimate(for: message)
            case .tool:
                return total + tokenEstimate(for: message)
            default:
                return total
            }
        }
    }

    private func trimOldestRecentTurns(to cap: Int) {
        guard cap >= 0 else { return }
        while estimatedRecentTurnTokens() > cap {
            guard let range = oldestRemovableRecentTurnRange() else { break }
            messages.removeSubrange(range)
        }
    }

    private func oldestRemovableRecentTurnRange() -> Range<Int>? {
        guard let firstNonSystem = messages.firstIndex(where: { $0.role != .system }) else { return nil }
        let message = messages[firstNonSystem]
        if message.role == .assistant, let calls = message.toolCalls, !calls.isEmpty {
            var end = firstNonSystem + 1
            while end < messages.count, messages[end].role == .tool {
                end += 1
            }
            return firstNonSystem..<end
        }
        return firstNonSystem..<(firstNonSystem + 1)
    }

    private func trimRAGInjection(to cap: Int) {
        guard cap >= 0 else { return }
        guard let firstSystemIndex = messages.firstIndex(where: { $0.role == .system }) else { return }

        while estimatedRAGTokens() > cap {
            guard let removalIndex = messages.indices.first(where: { $0 > firstSystemIndex && messages[$0].role == .system }) else {
                break
            }
            messages.remove(at: removalIndex)
        }
    }

    private func truncateSystemPrompt(to cap: Int) {
        guard cap >= 0 else { return }
        guard let index = messages.firstIndex(where: { $0.role == .system }) else { return }

        let originalText: String
        switch messages[index].content {
        case .text(let text):
            originalText = text
        case .parts(let parts):
            originalText = parts.map { part in
                switch part {
                case .text(let text): return text
                case .imageURL(let url): return url
                }
            }.joined(separator: " ")
        }

        guard tokenEstimate(forText: originalText) > cap else { return }
        let marker = "[truncated for budget]"
        let keepCount = max(0, min(originalText.count, cap * 4))
        let prefix = String(originalText.prefix(keepCount))
        let truncated = prefix.isEmpty ? marker : "\(prefix) \(marker)"
        messages[index].content = .text(truncated)
    }

    private func tokenEstimate(for message: Message) -> Int {
        var text = ""
        switch message.content {
        case .text(let s):
            text = s
        case .parts(let parts):
            text = parts.map { part in
                switch part {
                case .text(let s): return s
                case .imageURL(let s): return s
                }
            }.joined(separator: " ")
        }
        return Int(Double(text.utf8.count) / 3.5)
    }

    private func compact(force: Bool, customDigest: String? = nil) {
        let countBefore = messages.count
        let tokensBefore = estimatedTokens

        // Build exchange groups: one assistant message with toolCalls followed
        // immediately by one or more tool result messages.
        //
        // We MUST remove complete groups rather than lone tool results so the
        // context never contains an assistant message with `tool_calls` that
        // lacks its corresponding tool result messages.  Providers (DeepSeek,
        // OpenAI-compatible) reject such contexts with HTTP 400:
        // "An assistant message with 'tool_calls' must be followed by tool
        // messages responding to each 'tool_call_id'."
        struct ExchangeGroup {
            var assistantIdx: Int
            var toolIndices: [Int]
        }

        var groups: [ExchangeGroup] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            guard msg.role == .assistant,
                  let calls = msg.toolCalls,
                  !calls.isEmpty else {
                i += 1
                continue
            }
            // Collect all consecutive tool results that follow this assistant message.
            var toolIndices: [Int] = []
            var j = i + 1
            while j < messages.count && messages[j].role == .tool {
                toolIndices.append(j)
                j += 1
            }
            if !toolIndices.isEmpty {
                groups.append(ExchangeGroup(assistantIdx: i, toolIndices: toolIndices))
            }
            i = j
        }

        guard force || !groups.isEmpty else { return }

        let recentStart = max(0, messages.count - compactionKeepRecentTurns)
        let oldGroups = groups.filter { $0.assistantIdx < recentStart }
        let groupsToRemove: [ExchangeGroup]
        if force {
            groupsToRemove = oldGroups.isEmpty ? groups : oldGroups
        } else {
            groupsToRemove = oldGroups
        }

        guard force || !groupsToRemove.isEmpty else { return }

        if groupsToRemove.isEmpty && force {
            // No tool-exchange groups to remove. Hard-truncate to the most recent
            // `compactionKeepRecentTurns` messages so the context actually shrinks
            // even when it consists entirely of user/assistant text (no tool calls).
            // Without this, the old code just appended a sentinel string and left
            // the full context intact — causing HTTP 400s on the next LLM request.
            let kept = Array(messages.suffix(compactionKeepRecentTurns))
            let summary = Message(
                role: .system,
                content: .text("[context compacted — history truncated to last \(kept.count) messages]"),
                timestamp: Date()
            )
            messages = [summary] + kept
        } else {
            // Build the removal set: both assistant and tool result indices.
            let allIndices = Set(groupsToRemove.flatMap { [$0.assistantIdx] + $0.toolIndices })

            let digest = allIndices.sorted().map { idx -> String in
                let message = messages[idx]
                let preview: String
                switch message.content {
                case .text(let s):
                    preview = String(s.prefix(100))
                case .parts(let parts):
                    preview = String(parts.map { part in
                        switch part {
                        case .text(let s): return s
                        case .imageURL(let s): return s
                        }
                    }.joined(separator: " ").prefix(100))
                }
                return preview
            }.joined(separator: ", ")

            let summaryText = customDigest
                ?? "[context compacted — \(groupsToRemove.count) tool exchange(s) summarised] \(digest)"
            let summary = Message(
                role: .system,
                content: .text(summaryText),
                timestamp: Date()
            )

            var rebuilt: [Message] = []
            for (index, message) in messages.enumerated() {
                if allIndices.contains(index) { continue }
                rebuilt.append(message)
            }
            rebuilt.insert(summary, at: min(recentStart, rebuilt.count))
            messages = rebuilt
        }

        let skillBlock = buildSkillReinjectionBlock(
            skills: recentlyInvokedSkills,
            disabledNames: AppSettings.shared.disabledSkillNames
        )
        if !skillBlock.isEmpty {
            messages.append(Message(
                role: .system,
                content: .text(skillBlock),
                timestamp: Date()
            ))
        }

        estimatedTokens = recomputeEstimatedTokens()
        compactionCount += 1
        TelemetryEmitter.shared.emit("context.compaction", data: [
            "message_count_before": countBefore,
            "message_count_after": messages.count,
            "tokens_before": tokensBefore,
            "tokens_after": estimatedTokens,
            "forced": force
        ])
    }

    func buildSkillReinjectionBlock(skills: [Skill], disabledNames: [String] = []) -> String {
        let visibleSkills = disabledNames.isEmpty
            ? skills
            : skills.filter { !disabledNames.contains($0.name) }
        guard visibleSkills.isEmpty == false else { return "" }

        var parts: [String] = []
        var tokensSoFar = 0

        for skill in visibleSkills {
            let section = "## \(skill.name)\n\(skill.body)"
            let tokens = tokenEstimate(forText: section)
            guard tokens <= skillBudgetPerSkill else { continue }
            guard tokensSoFar + tokens <= skillBudgetTokens else { break }
            parts.append(section)
            tokensSoFar += tokens
        }

        guard !parts.isEmpty else { return "" }
        return "[Skills]\n" + parts.joined(separator: "\n\n") + "\n[/Skills]"
    }

    private func tokenEstimate(forText text: String) -> Int {
        Int(Double(text.utf8.count) / 3.5)
    }
}
