import Foundation

@MainActor
final class ContextManager: ObservableObject {
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

    func messagesForProvider() -> [Message] {
        messages
    }

    func forceCompaction() {
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
        let toolIndices = messages.indices.filter { messages[$0].role == .tool }
        guard force || !toolIndices.isEmpty else { return }

        let recentStart = max(0, messages.count - compactionKeepRecentTurns)
        let oldToolIndices = toolIndices.filter { $0 < recentStart }
        guard force || !oldToolIndices.isEmpty else { return }

        if oldToolIndices.isEmpty && force {
            messages.append(Message(
                role: .system,
                content: .text("[context compacted]"),
                timestamp: Date()
            ))
        } else {
            let digest = oldToolIndices.map { idx in
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
                content: .text("[context compacted — \(oldToolIndices.count) tool results summarised] \(digest)"),
                timestamp: Date()
            )

            var rebuilt: [Message] = []
            for (index, message) in messages.enumerated() {
                if oldToolIndices.contains(index) {
                    continue
                }
                rebuilt.append(message)
            }
            rebuilt.insert(summary, at: min(recentStart, rebuilt.count))
            messages = rebuilt
        }

        if let skillBlock = buildSkillReinjectionBlock(), !skillBlock.isEmpty {
            messages.append(Message(
                role: .system,
                content: .text(skillBlock),
                timestamp: Date()
            ))
        }

        estimatedTokens = recomputeEstimatedTokens()
        compactionCount += 1
    }

    private func buildSkillReinjectionBlock() -> String? {
        guard !recentlyInvokedSkills.isEmpty else { return nil }

        var parts: [String] = []
        var tokensSoFar = 0

        for skill in recentlyInvokedSkills {
            let section = "## \(skill.name)\n\(skill.body)"
            let tokens = tokenEstimate(forText: section)
            guard tokens <= skillBudgetPerSkill else { continue }
            guard tokensSoFar + tokens <= skillBudgetTokens else { break }
            parts.append(section)
            tokensSoFar += tokens
        }

        guard !parts.isEmpty else { return nil }
        return "[Skills]\n" + parts.joined(separator: "\n\n") + "\n[/Skills]"
    }

    private func tokenEstimate(forText text: String) -> Int {
        Int(Double(text.utf8.count) / 3.5)
    }
}
