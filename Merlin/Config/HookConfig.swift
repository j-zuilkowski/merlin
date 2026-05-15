import Foundation

enum HookEvent: String, Codable, Sendable, CaseIterable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case sessionStart = "SessionStart"
}

struct HookConfig: Codable, Sendable, Identifiable {
    var id: String { "\(event):\(command)" }
    var event: String
    var command: String
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case event
        case command
        case enabled
    }

    init(event: String, command: String, enabled: Bool = true) {
        self.event = event
        self.command = command
        self.enabled = enabled
    }

    init(event: HookEvent, command: String, enabled: Bool = true) {
        self.init(event: event.rawValue, command: command, enabled: enabled)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        command = try container.decode(String.self, forKey: .command)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(command, forKey: .command)
        try container.encode(enabled, forKey: .enabled)
    }
}
