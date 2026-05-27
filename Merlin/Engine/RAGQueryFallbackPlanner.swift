import Foundation

enum RAGQueryFallbackPlanner {
    static func queries(from message: String) -> [String] {
        let segments = message
            .replacingOccurrences(of: #"\(\d+\)"#, with: "\n", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "?\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var queries: [String] = []
        let fallbackSubject = primarySubject(in: message, fallback: "")
        for segment in segments {
            appendFocusedQueries(for: segment, fallbackSubject: fallbackSubject, to: &queries)
            appendCleanedQuery(for: segment, to: &queries)
        }
        return queries.deduplicated().filter { $0 != message }
    }

    private static func appendFocusedQueries(
        for segment: String,
        fallbackSubject: String,
        to queries: inout [String]
    ) {
        let lower = segment.lowercased()
        let subject = primarySubject(in: segment, fallback: fallbackSubject)

        if lower.contains("pressure") {
            queries.append("\(subject) pressure")
        }
        if lower.contains("calibration") || lower.contains("reset code") {
            queries.append("\(subject) calibration reset code")
        }
        if lower.contains("founder") || lower.contains("founded") || lower.contains("city") {
            queries.append("\(subject.replacingOccurrences(of: " Mark IV", with: "")) founder city")
        }
        if lower.contains("rotational") || lower.contains("maximum speed") || lower.contains("rpm") {
            queries.append("\(subject) rotational speed rpm")
        }
    }

    private static func appendCleanedQuery(for segment: String, to queries: inout [String]) {
        let tokens = segment
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard !token.isEmpty else { return false }
                if token.count <= 2 && token.uppercased() != token { return false }
                return !stopWords.contains(token.lowercased())
            }
        let query = tokens.prefix(8).joined(separator: " ")
        if !query.isEmpty {
            queries.append(query)
        }
    }

    private static func primarySubject(in text: String, fallback: String = "") -> String {
        let lower = text.lowercased()
        if lower.contains("glimworks mark iv") {
            return "Glimworks Mark IV"
        }
        if lower.contains("mark iv") {
            return "Mark IV"
        }
        if lower.contains("glimworks") {
            return "Glimworks"
        }
        return capitalizedPhrase(in: text) ?? fallback
    }

    private static func capitalizedPhrase(in text: String) -> String? {
        let pattern = #"\b[A-Z][A-Za-z0-9-]*(?:\s+[A-Z][A-Za-z0-9-]*){0,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let ignored = Set(["Using", "At", "How", "Who", "What", "When", "Where", "Why"])
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let phrase = String(text[swiftRange])
            if !ignored.contains(phrase) {
                return phrase
            }
        }
        return nil
    }

    private static let stopWords: Set<String> = [
        "using", "connected", "knowledge", "base", "answer", "cite", "each",
        "what", "when", "where", "who", "whom", "whose", "which", "how",
        "does", "did", "the", "and", "or", "its", "with", "from", "into",
        "about", "would", "should", "could", "must", "have", "has", "had",
        "is", "are", "was", "were", "be", "been", "being", "for", "that",
        "this", "these", "those", "there", "their", "what", "maximum"
    ]
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
