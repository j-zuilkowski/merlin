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

    /// Token count above which `compactIfNeededBeforeRun` fires automatically.
    /// Kept well below a typical 32 K model context so the model has ample
    /// output space even in long sessions.
    let preRunCompactionThreshold = 10_000

    /// Token threshold that triggers compaction mid-loop, inside the `while true` execute loop.
    /// A `var` so tests can lower it without mocking. Default: 40 000 tokens —
    /// well below a typical 32 K model context, giving the next LLM call ample output headroom.
    var midLoopCompactionThreshold: Int = 40_000

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

    private func compact(force: Bool) {
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

            let summary = Message(
                role: .system,
                content: .text(
                    "[context compacted — \(groupsToRemove.count) tool exchange(s) summarised] \(digest)"
                ),
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
