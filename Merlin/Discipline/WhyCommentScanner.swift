import Foundation

struct WhyCommentTrigger: Sendable {
    let pattern: String
    let reason: String
    let file: String
    let line: Int
    let context: String
    let hasNearbyComment: Bool
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
            guard line.range(of: spec.regex, options: .regularExpression) != nil else { continue }
            if line.contains("rationale-not-needed:") { continue }

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

            results.append(WhyCommentTrigger(
                pattern: spec.regex,
                reason: spec.reason,
                file: file,
                line: idx + 1,
                context: contextStr,
                hasNearbyComment: hasComment
            ))
        }

        return results
    }
}
