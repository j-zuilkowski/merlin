import Foundation

enum PatternMatcher {
    static func matches(value: String, pattern: String) -> Bool {
        let expandedPattern = expandHome(pattern)
        let regexPattern = "^" + globToRegex(expandedPattern) + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    private static func expandHome(_ pattern: String) -> String {
        guard pattern.hasPrefix("~") else { return pattern }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + pattern.dropFirst()
    }

    private static func globToRegex(_ pattern: String) -> String {
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let ch = pattern[index]
            if ch == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    result += ".*"
                    index = pattern.index(after: next)
                } else {
                    result += "[^/]*"
                    index = next
                }
                continue
            }
            result += NSRegularExpression.escapedPattern(for: String(ch))
            index = pattern.index(after: index)
        }
        return result
    }
}
