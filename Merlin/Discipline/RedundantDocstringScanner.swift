import Foundation

// MARK: - RedundantDocstring

/// A single redundant-docstring finding produced by `RedundantDocstringScanner`.
struct RedundantDocstring: Sendable, Equatable {
    let file: String
    let line: Int
    let symbolName: String
    let docComment: String
    let reason: Reason

    enum Reason: Sendable, Equatable {
        /// The doc-comment body restates the symbol identifier with no additional information.
        case restatesIdentifier
        /// The doc-comment opens with a known WHAT-phrase (`Returns the …`, `The …`, etc.)
        /// and adds no quantitative or example information.
        case knownWhatPhrase
        /// A `///` block of 4+ lines with no `Why:`/`Note:`/`Important:` marker and no
        /// content-bearing annotations (numeric ranges, examples, backtick code refs).
        case multiLineWithoutWhyMarker
    }
}

// MARK: - RedundantDocstringScanner

/// Scans Swift source files for `///` doc-comment blocks that violate the project's
/// "no WHAT-comments" rule (see CLAUDE.md). Three heuristics: identifier-restatement,
/// known WHAT-phrase prefixes, and multi-line blocks without a structural marker.
///
/// Suppressed by content-bearing markers (numeric ranges like `[0, 1]`, examples
/// like `E.g.`, backticked code refs) and by an inline
/// `// docstring-not-redundant: <reason>` override on the symbol declaration line.
actor RedundantDocstringScanner {

    /// Verb-led WHAT-phrase regexes — the dominant API-doc noise pattern (`Returns the X`,
    /// `Sets the Y`, `Holds the Z`). Checked before `restatesIdentifier` so verbalised
    /// accessors classify as `knownWhatPhrase` even when they happen to contain the identifier.
    private static let verbLedWhatPatterns: [String] = [
        #"(?i)^returns?\s+"#,
        #"(?i)^sets?\s+"#,
        #"(?i)^gets?\s+"#,
        #"(?i)^holds?\s+"#,
        #"(?i)^stores?\s+"#,
        #"(?i)^indicates?\s+"#,
        #"(?i)^manages?\s+"#,
        #"(?i)^represents?\s+"#,
        #"(?i)^contains?\s+"#,
        #"(?i)^human-readable\s+"#,
    ]

    /// Article-led WHAT-phrase regexes — checked after `restatesIdentifier` so that
    /// `The X content of the Y` on identifier `X` is classified as restatement, not as the
    /// weaker article-led category.
    private static let articleLedWhatPatterns: [String] = [
        #"(?i)^the\s+\S+"#,
        #"(?i)^a\s+\S+"#,
        #"(?i)^an\s+\S+"#,
    ]

    /// Markers whose presence in the doc body always suppresses a finding. They identify
    /// docstrings that earn their keep with rationale, examples, or pointers.
    private static let suppressionMarkers: [String] = [
        "Why:", "Note:", "Important:", "Warning:", "rationale:", "See:", "TODO:", "FIXME:",
    ]

    /// Walks the project root and returns all findings from non-test `*.swift` files.
    func scan(projectPath: String) async -> [RedundantDocstring] {
        var results: [RedundantDocstring] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return results }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  !url.path.contains("/Tests/"),
                  !url.path.contains("Tests/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            results.append(contentsOf: scan(text: text, file: url.path))
        }
        return results
    }

    /// Scans a single file's text. Public for testability against in-memory fixtures.
    nonisolated func scan(text: String, file: String) -> [RedundantDocstring] {
        var results: [RedundantDocstring] = []
        let lines = text.components(separatedBy: .newlines)
        var idx = 0

        while idx < lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("///") else { idx += 1; continue }

            var blockEnd = idx
            while blockEnd + 1 < lines.count {
                let next = lines[blockEnd + 1].trimmingCharacters(in: .whitespaces)
                if next.hasPrefix("///") {
                    blockEnd += 1
                } else {
                    break
                }
            }

            // The declaration line is the first non-`///`, non-blank line after the block.
            var symbolLineIdx = blockEnd + 1
            while symbolLineIdx < lines.count {
                let s = lines[symbolLineIdx].trimmingCharacters(in: .whitespaces)
                if s.isEmpty {
                    symbolLineIdx += 1
                    continue
                }
                break
            }
            let symbolLine = symbolLineIdx < lines.count ? lines[symbolLineIdx] : ""

            if symbolLine.contains("docstring-not-redundant:") {
                idx = blockEnd + 1
                continue
            }

            let block = Array(lines[idx...blockEnd])
            let symbolName = Self.extractIdentifier(from: symbolLine) ?? ""

            if let finding = Self.analyze(
                block: block,
                symbolName: symbolName,
                file: file,
                line: idx + 1
            ) {
                results.append(finding)
            }

            idx = blockEnd + 1
        }
        return results
    }

    private static func analyze(
        block: [String],
        symbolName: String,
        file: String,
        line: Int
    ) -> RedundantDocstring? {
        let bodyLines = block.map { line -> String in
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("///") { s.removeFirst(3) }
            return s.trimmingCharacters(in: .whitespaces)
        }
        let body = bodyLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        // Structural markers — any of them spares the block.
        for marker in suppressionMarkers where body.contains(marker) {
            return nil
        }

        // Content-bearing markers: numeric ranges, examples, backtick code refs, numbers.
        let hasRange = body.range(of: #"\[[^\]]+\]"#, options: .regularExpression) != nil
        let hasExample = body.range(of: #"(?i)\be\.g\.?\b"#, options: .regularExpression) != nil
        let hasCodeRef = body.contains("`")
        let hasNumber = body.range(of: #"\b\d+([.,]\d+)?\b"#, options: .regularExpression) != nil
        let isContentBearing = hasRange || hasExample || hasCodeRef || hasNumber

        // Multi-line check first — 4+ `///` lines without any of the suppressors above.
        if block.count >= 4 && !isContentBearing {
            return RedundantDocstring(
                file: file, line: line,
                symbolName: symbolName,
                docComment: body,
                reason: .multiLineWithoutWhyMarker
            )
        }

        // Single-block content-bearing comments are fine.
        if isContentBearing { return nil }

        let firstSentence = body.split(separator: ".").first.map(String.init) ?? body

        // Verb-led WHAT (Returns/Sets/Gets/…) wins first — strong signal regardless of
        // whether the body also happens to contain the identifier.
        for pattern in verbLedWhatPatterns where firstSentence.range(of: pattern, options: .regularExpression) != nil {
            return RedundantDocstring(
                file: file, line: line,
                symbolName: symbolName,
                docComment: body,
                reason: .knownWhatPhrase
            )
        }

        // Identifier-restatement check: more specific than the article-led pattern
        // ("The X content of the Y" on identifier `X` belongs here, not in WHAT).
        if !symbolName.isEmpty,
           restatesIdentifier(firstSentence: firstSentence, identifier: symbolName) {
            return RedundantDocstring(
                file: file, line: line,
                symbolName: symbolName,
                docComment: body,
                reason: .restatesIdentifier
            )
        }

        // Article-led WHAT (The/A/An …) — weakest category, catches docstrings that
        // open with a generic article phrase and don't reference the identifier directly.
        for pattern in articleLedWhatPatterns where firstSentence.range(of: pattern, options: .regularExpression) != nil {
            return RedundantDocstring(
                file: file, line: line,
                symbolName: symbolName,
                docComment: body,
                reason: .knownWhatPhrase
            )
        }

        return nil
    }

    /// Returns the declared identifier from a Swift declaration line, if any.
    private static func extractIdentifier(from line: String) -> String? {
        let pattern = #"^\s*(?:(?:public|private|internal|fileprivate|open|nonisolated|static|final|weak|unowned|@\w+(?:\([^)]*\))?)\s+)*(?:let|var|func|struct|class|enum|case|protocol|actor|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    /// True when the docstring's first sentence is short and contains every camelCase
    /// token of the identifier — the signature of a restatement.
    private static func restatesIdentifier(firstSentence: String, identifier: String) -> Bool {
        guard identifier.count >= 4 else { return false }
        let words = firstSentence.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.count <= 12 else { return false }
        let tokens = splitCamelCase(identifier).map { $0.lowercased() }
        let lowered = firstSentence.lowercased()
        return tokens.allSatisfy { lowered.contains($0) }
    }

    /// Splits `identifier` into its camelCase components. `fooBarBaz` → `["foo", "Bar", "Baz"]`.
    private static func splitCamelCase(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch.isUppercase && !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
