import Foundation

enum HTMLTextExtractor {
    static func extractTitle(from html: String) -> String? {
        html.firstRegexCapture(pattern: #"<title[^>]*>(.*?)</title>"#)?.strippingHTML().htmlDecoded().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?is)<script.*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<style.*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<nav.*?</nav>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<footer.*?</footer>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
        text = text.strippingHTML().htmlDecoded()
        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    }

    func htmlDecoded() -> String {
        var result = self
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    func regexMatches(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsrange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsrange).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: self) else { return "" }
                return String(self[range])
            }
        }
    }

    func firstRegexCapture(pattern: String) -> String? {
        regexMatches(pattern: pattern).first?.dropFirst().first
    }
}
