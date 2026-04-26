import Foundation

enum ThinkingModeDetector {
    private static let enabledSignals = ["debug", "why", "architecture", "design", "explain", "error", "failing", "unexpected", "broken", "investigate"]
    private static let disabledSignals = ["read", "write", "run", "list", "build", "open", "create", "delete", "move", "show"]

    static func shouldEnableThinking(for message: String) -> Bool {
        for word in disabledSignals where containsWholeWord(word, in: message) {
            return false
        }

        return enabledSignals.contains { containsWholeWord($0, in: message) }
    }

    static func config(for message: String) -> ThinkingConfig {
        if shouldEnableThinking(for: message) {
            return ThinkingConfig(type: "enabled", reasoningEffort: "high")
        }
        return ThinkingConfig(type: "disabled", reasoningEffort: nil)
    }

    private static func containsWholeWord(_ word: String, in message: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return regex.firstMatch(in: message, options: [], range: range) != nil
    }
}
