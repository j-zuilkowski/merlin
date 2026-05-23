import Foundation

/// Built-in slash commands that the chat input handles directly (via
/// `SlashCommandHandler` and the inline branches in `ChatView`).
///
/// These are distinct from user-loaded skills in `~/.merlin/skills/` — the
/// SkillsPicker shows both in separate sections so users can discover them
/// without consulting documentation.
struct BuiltinSlashCommand: Sendable, Equatable {
    let name: String
    let description: String
}

enum BuiltinSlashCommands {

    /// Canonical list shown by the picker. Order is part of the UI contract
    /// (see BuiltinSlashCommandsTests.testStableOrdering): `calibrate` first
    /// (the most-discoverable workflow command), then the other three
    /// alphabetically.
    static let all: [BuiltinSlashCommand] = [
        BuiltinSlashCommand(
            name: "calibrate",
            description: "Benchmark the active local model against a reference provider (18-prompt battery)."
        ),
        BuiltinSlashCommand(
            name: "btw",
            description: "Ask a one-shot side question in a floating overlay; doesn't touch session context."
        ),
        BuiltinSlashCommand(
            name: "compact",
            description: "Compact the context window on demand (removes oldest tool exchanges)."
        ),
        BuiltinSlashCommand(
            name: "rewind",
            description: "Restore the previous checkpoint (or N steps back: /rewind 3)."
        ),
    ]

    /// Filters the canonical list by a case-insensitive query that matches
    /// either the command name or its description. Empty query returns all.
    static func matching(query: String) -> [BuiltinSlashCommand] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { cmd in
            cmd.name.lowercased().contains(q) ||
            cmd.description.lowercased().contains(q)
        }
    }
}
