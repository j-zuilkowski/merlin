import Foundation

struct WhyCommentTrigger: Sendable {
    let pattern: String
    let reason: String
    let file: String
    let line: Int
    let context: String
    let hasNearbyComment: Bool
    /// Non-nil when the trigger line carries an inline `rationale-not-needed:`
    /// annotation — the trigger is an acknowledged override rather than a violation.
    let overrideRationale: String?
}

/// Scans source files for adapter-defined WHY-trigger patterns and checks for
/// nearby explanatory comments.
actor WhyCommentScanner {

    func scan(projectPath: String, adapter: ProjectAdapter) async -> [WhyCommentTrigger] {
        guard !adapter.whyCommentTriggers.isEmpty else { return [] }
        var results: [WhyCommentTrigger] = []

        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return results }

        while let url = enumerator.nextObject() as? URL {
            guard (url.pathExtension == "swift" || url.pathExtension == "rs"),
                  !url.path.contains("Tests/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = text.components(separatedBy: .newlines)
            for triggerSpec in adapter.whyCommentTriggers {
                results.append(contentsOf: scanLines(lines, file: url.path, spec: triggerSpec))
            }
        }

        return results
    }

    private func scanLines(
        _ lines: [String],
        file: String,
        spec: WHYTriggerSpec
    ) -> [WhyCommentTrigger] {
        var results: [WhyCommentTrigger] = []

        for (idx, line) in lines.enumerated() {
            guard let matchRange = line.range(of: spec.regex, options: .regularExpression) else {
                continue
            }
            // A trigger pattern that only appears inside a // comment or a string
            // literal is discussion, not code - skip it so the gate does not block
            // legitimate commits on false positives.
            if isInsideCommentOrString(line: line, matchStart: matchRange.lowerBound) {
                continue
            }

            let windowStart = max(0, idx - 2)
            let windowEnd = min(lines.count - 1, idx + 2)
            let contextStr = lines[windowStart...windowEnd].joined(separator: "\n")

            let commentStart = max(0, idx - 3)
            let commentEnd = min(lines.count - 1, idx + 3)
            let commentWindow = lines[commentStart...commentEnd]
            let hasComment = commentWindow.contains { commentLine in
                let t = commentLine.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("//") || t.hasPrefix("#") || t.hasPrefix("/*")) &&
                    !t.contains("rationale-not-needed:")
            }

            let override = OverrideAnnotationParser().parse(line: line)
            results.append(WhyCommentTrigger(
                pattern: spec.regex,
                reason: spec.reason,
                file: file,
                line: idx + 1,
                context: contextStr,
                hasNearbyComment: hasComment,
                overrideRationale: override?.rationale
            ))
        }

        return results
    }

    /// True when `matchStart` lies inside a `//` line comment or a `"..."` string
    /// literal on `line`.
    ///
    /// Heuristic, not a full lexer: it scans the prefix of the line up to the match.
    /// - If a `//` occurs before the match while not inside quotes, the match is in a
    ///   comment.
    /// - The count of unescaped `"` characters before the match: an odd count means
    ///   the match sits inside an open string literal.
    private func isInsideCommentOrString(line: String, matchStart: String.Index) -> Bool {
        var insideString = false
        var previous: Character?
        var index = line.startIndex

        while index < matchStart {
            let ch = line[index]
            if ch == "\"" && previous != "\\" {
                insideString.toggle()
            } else if ch == "/" && previous == "/" && !insideString {
                // A "//" reached before the match, outside any string -> comment.
                return true
            }
            previous = ch
            index = line.index(after: index)
        }

        // If we ended the prefix scan still inside a string, the match is in a literal.
        return insideString
    }
}
